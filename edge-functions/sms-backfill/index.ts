import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ==== ENV ====
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

interface ParsedSms {
  trxId: string | null
  amount: number | null
  method: string | null
  senderNumber: string | null
  txnType: string | null
}

function parseSms(sender: string, body: string): ParsedSms {
  const s = (sender || '').toLowerCase()
  const b = body || ''

  let method: string | null = null
  if (s.includes('bkash') || /\bbkash\b/i.test(b)) method = 'bKash'
  else if (s.includes('nagad') || /\bnagad\b/i.test(b)) method = 'Nagad'
  else if (s.includes('rocket') || s.includes('dbbl') || /\brocket\b/i.test(b)) method = 'Rocket'

  let txnType: string | null = null
  if (/cash\s*in|uddokta/i.test(b)) txnType = 'cash_in'
  else if (/mobile\s*recharge|recharge\s*request/i.test(b)) txnType = 'mobile_recharge'
  else if (/bill\s*pay/i.test(b)) txnType = 'bill_pay'
  else if (/merchant/i.test(b)) txnType = 'merchant_payment'
  else if (/received|পেয়েছেন|credited/i.test(b)) txnType = 'send_money'

  let senderNumber: string | null = null
  const labeled = b.match(/(?:from|sender|uddokta|প্রেরক|উদ্দোক্তা)[:\s]*?(01\d{9})/i)
  if (labeled) senderNumber = labeled[1]
  else {
    const anyNumber = b.match(/\b(01\d{9})\b/)
    if (anyNumber) senderNumber = anyNumber[1]
  }

  if (txnType !== 'send_money') {
    return { trxId: null, amount: null, method, senderNumber, txnType }
  }

  const amountMatch = b.match(/(?:tk\.?|৳)\s?([\d,]+(?:\.\d{1,2})?)/i)
  const amount = amountMatch ? parseFloat(amountMatch[1].replace(/,/g, '')) : null

  const trxMatch = b.match(/(?:trx\s?id|txn\s?id|transaction\s?id|ট্রানজেকশন\s?আইডি)[:\s]*([A-Za-z0-9]{6,})/i)
  const trxId = trxMatch ? trxMatch[1].toUpperCase() : null

  return { trxId, amount, method, senderNumber, txnType }
}

Deno.serve(async (req: Request) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'content-type, authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  }
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const token = authHeader.replace(/^Bearer\s+/i, '')
    if (!token) {
      return new Response(JSON.stringify({ status: 'unauthorized' }), { status: 401, headers: cors })
    }

    const { data: userData, error: userErr } = await admin.auth.getUser(token)
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ status: 'unauthorized' }), { status: 401, headers: cors })
    }

    const { data: adminRow } = await admin.from('admins').select('id').eq('id', userData.user.id).maybeSingle()
    if (!adminRow) {
      return new Response(JSON.stringify({ status: 'forbidden', message: 'শুধুমাত্র অ্যাডমিন এই কাজ করতে পারবে' }), { status: 403, headers: cors })
    }

    const payload = await req.json().catch(() => null)
    if (!payload) {
      return new Response(JSON.stringify({ status: 'bad_request' }), { status: 400, headers: cors })
    }

    const rawMessages: Array<{ sender?: string; body: string }> = Array.isArray(payload.messages)
      ? payload.messages
      : [{ sender: payload.sender, body: payload.body }]

    const results = []
    for (const m of rawMessages) {
      if (!m || typeof m.body !== 'string' || !m.body.trim()) {
        results.push({ status: 'bad_message' })
        continue
      }
      const sender = m.sender ?? ''
      const body = m.body

      const { trxId, amount, method, senderNumber, txnType } = parseSms(sender, body)

      const { data, error } = await admin.rpc('process_sms_payment', {
        p_trx_id: trxId,
        p_amount: amount,
        p_method: method,
        p_raw_sender: sender,
        p_raw_body: body,
        p_sender_number: senderNumber,
        p_txn_type: txnType,
      })

      results.push(error ? { status: 'error', message: error.message, body } : { ...data, body })
    }

    return new Response(JSON.stringify({ status: 'done', results }), {
      status: 200,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    console.log('sms-backfill exception:', String(e))
    return new Response(JSON.stringify({ status: 'error', message: String(e) }), { status: 500, headers: cors })
  }
})
