import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FCM_PROJECT_ID = Deno.env.get('FCM_PROJECT_ID')!
const FCM_CLIENT_EMAIL = Deno.env.get('FCM_CLIENT_EMAIL')!
const FCM_PRIVATE_KEY = Deno.env.get('FCM_PRIVATE_KEY')!.replace(/\\n/g, '\n')

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

function base64url(input: ArrayBuffer | string): string {
  let bytes: Uint8Array
  if (typeof input === 'string') {
    bytes = new TextEncoder().encode(input)
  } else {
    bytes = new Uint8Array(input)
  }
  let str = ''
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function getAccessToken(): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' }
  const now = Math.floor(Date.now() / 1000)
  const claim = {
    iss: FCM_CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  const encodedHeader = base64url(JSON.stringify(header))
  const encodedClaim = base64url(JSON.stringify(claim))
  const signingInput = `${encodedHeader}.${encodedClaim}`

  const pemContents = FCM_PRIVATE_KEY
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput)
  )

  const jwt = `${signingInput}.${base64url(signature)}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const data = await res.json()
  if (!data.access_token) throw new Error('FCM_AUTH_FAILED: ' + JSON.stringify(data))
  return data.access_token
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json()
    const record = payload.record

    if (!FCM_PROJECT_ID || !FCM_CLIENT_EMAIL || !FCM_PRIVATE_KEY) {
      console.error('BRIGHT-API: FCM env vars missing! Set FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY in Supabase secrets.')
      return new Response(JSON.stringify({ ok: false, error: 'FCM_ENV_MISSING' }), { status: 200 })
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    let tokens: string[] = []
    if (record.to_user_id) {
      const { data } = await supabase.from('device_fcm_tokens').select('token').eq('user_id', record.to_user_id)
      tokens = (data || []).map((t: any) => t.token)
    } else {
      const { data } = await supabase.from('device_fcm_tokens').select('token')
      tokens = (data || []).map((t: any) => t.token)
    }

    console.log(`BRIGHT-API: sending to ${tokens.length} token(s), to_user_id=${record.to_user_id || 'broadcast'}`)

    if (tokens.length === 0) {
      console.log('BRIGHT-API: no tokens found, nothing sent')
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'no_tokens' }), { status: 200 })
    }

    let accessToken: string
    try {
      accessToken = await getAccessToken()
    } catch(e) {
      console.error('BRIGHT-API: getAccessToken failed:', String(e))
      return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 200 })
    }

    let sent = 0
    let failed = 0
    const staleTokens: string[] = []

    for (const token of tokens) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: record.title, body: record.body },
            android: {
              priority: 'high',
              notification: {
                channel_id: 'oxn_high_priority',
                sound: 'default',
                notification_priority: 'PRIORITY_MAX',
              },
            },
          },
        }),
      })

      if (res.ok) {
        sent++
      } else {
        failed++
        const errText = await res.text()
        console.error(`BRIGHT-API: FCM failed status=${res.status} token_prefix=${token.substring(0,20)}... error=${errText}`)
        if (errText.includes('UNREGISTERED') || errText.includes('INVALID_ARGUMENT')) {
          staleTokens.push(token)
        }
      }
    }

    if (staleTokens.length > 0) {
      await supabase.from('device_fcm_tokens').delete().in('token', staleTokens)
      console.log(`BRIGHT-API: removed ${staleTokens.length} stale token(s)`)
    }

    console.log(`BRIGHT-API: done. sent=${sent}, failed=${failed}, stale_removed=${staleTokens.length}`)
    return new Response(JSON.stringify({ ok: true, sent, failed, stale_removed: staleTokens.length }), { status: 200 })
  } catch (e) {
    console.error('BRIGHT-API: unexpected error:', String(e))
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 })
  }
})
