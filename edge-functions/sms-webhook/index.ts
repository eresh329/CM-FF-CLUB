import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ==== ENV ====
// SUPABASE_URL এবং SUPABASE_SERVICE_ROLE_KEY Supabase Edge Functions এ অটো-ইনজেক্টেড থাকে।
// SMS_WEBHOOK_SECRET আলাদাভাবে সেট করতে হবে (Dashboard → Edge Functions → sms-webhook → Secrets)।
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const SMS_WEBHOOK_SECRET = Deno.env.get('SMS_WEBHOOK_SECRET') ?? ''

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

interface ParsedSms {
  trxId: string | null
  amount: number | null
  method: string | null
  senderNumber: string | null
  txnType: string | null
}

// ==== SMS পার্সিং ====
// bKash / Nagad / Rocket থেকে আসা SMS থেকে amount, TrxID, sender number এবং transaction
// type বের করার চেষ্টা করে। শুধু genuine ব্যক্তিগত "Send Money" লেনদেনই গ্রহণযোগ্য —
// Cash In (এজেন্ট), Mobile Recharge, Bill Pay, Merchant Payment বাদ দেওয়া হয়, কারণ এগুলো
// কোনো কাস্টমারের আসল পেমেন্ট না। Parsing এখানে (সার্ভারে) থাকায় ফরম্যাট বদলালে অ্যাপ
// রিবিল্ড ছাড়াই ঠিক করা যাবে।
function parseSms(sender: string, body: string): ParsedSms {
  const s = (sender || '').toLowerCase()
  const b = body || ''

  let method: string | null = null
  if (s.includes('bkash') || /\bbkash\b/i.test(b)) method = 'bKash'
  else if (s.includes('nagad') || /\bnagad\b/i.test(b)) method = 'Nagad'
  else if (s.includes('rocket') || s.includes('dbbl') || /\brocket\b/i.test(b)) method = 'Rocket'

  // ট্রানজেকশনের ধরন চিহ্নিত করা — Cash In / Recharge / Bill Pay / Merchant হলে বাতিল
  let txnType: string | null = null
  if (/cash\s*in|uddokta/i.test(b)) txnType = 'cash_in'
  else if (/mobile\s*recharge|recharge\s*request/i.test(b)) txnType = 'mobile_recharge'
  else if (/bill\s*pay/i.test(b)) txnType = 'bill_pay'
  else if (/merchant/i.test(b)) txnType = 'merchant_payment'
  else if (/received|পেয়েছেন|credited/i.test(b)) txnType = 'send_money'

  // sender এর নম্বর বের করার চেষ্টা — "from"/"Sender:"/"Uddokta:" এর পাশে থাকা BD মোবাইল নম্বর
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

  // amount: "Tk 500.00" / "Tk. 500" / "৳500" — প্রথম amount নেয় (সাধারণত "Amount:" লাইনেই থাকে)
  const amountMatch = b.match(/(?:tk\.?|৳)\s?([\d,]+(?:\.\d{1,2})?)/i)
  const amount = amountMatch ? parseFloat(amountMatch[1].replace(/,/g, '')) : null

  // TrxID: "TrxID ABC123XYZ" / "TxnID: ABC123" / "ট্রানজেকশন আইডি ABC123"
  const trxMatch = b.match(/(?:trx\s?id|txn\s?id|transaction\s?id|ট্রানজেকশন\s?আইডি)[:\s]*([A-Za-z0-9]{6,})/i)
  const trxId = trxMatch ? trxMatch[1].toUpperCase() : null

  return { trxId, amount, method, senderNumber, txnType }
}

Deno.serve(async (req: Request) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'content-type, x-sms-secret',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  }
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    // শেয়ার্ড সিক্রেট ভ্যালিডেশন — শুধু বিশ্বস্ত SMS-forwarder ডিভাইসই এই এন্ডপয়েন্ট কল করতে পারবে
    const secret = req.headers.get('x-sms-secret') ?? ''
    if (!SMS_WEBHOOK_SECRET || secret !== SMS_WEBHOOK_SECRET) {
      return new Response(JSON.stringify({ status: 'unauthorized' }), { status: 401, headers: cors })
    }

    const payload = await req.json().catch(() => null)
    if (!payload || typeof payload.body !== 'string') {
      return new Response(JSON.stringify({ status: 'bad_request' }), { status: 400, headers: cors })
    }

    const sender: string = payload.sender ?? ''
    const body: string = payload.body

    const { trxId, amount, method, senderNumber, txnType } = parseSms(sender, body)

    // process_sms_payment (SECURITY DEFINER, শুধু service_role/postgres এক্সিকিউট করতে পারে)
    // ভেতরে txn_type চেক + atomic duplicate-guard + ম্যাচিং + ক্রেডিট সব করে।
    const { data, error } = await supabase.rpc('process_sms_payment', {
      p_trx_id: trxId,
      p_amount: amount,
      p_method: method,
      p_raw_sender: sender,
      p_raw_body: body,
      p_sender_number: senderNumber,
      p_txn_type: txnType,
    })

    if (error) {
      console.log('process_sms_payment error:', error.message)
      return new Response(JSON.stringify({ status: 'error', message: error.message }), { status: 500, headers: cors })
    }

    return new Response(JSON.stringify(data), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    console.log('sms-webhook exception:', String(e))
    return new Response(JSON.stringify({ status: 'error', message: String(e) }), { status: 500, headers: cors })
  }
})
