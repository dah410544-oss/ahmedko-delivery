import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const json = (status = 200, body = {}, headers = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });

const failure = (status = 500, message = "") => {
  console.error(message);
  return json(
    status,
    { error: { http_code: status, message } },
    status === 503 ? { "retry-after": "true" } : {},
  );
};

const hmacHex = async (secret = "", text = "") => {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(text));
  return Array.from(new Uint8Array(mac), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
};

const wait = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms));

Deno.serve(async (req) => {
  const apiKey = (Deno.env.get("BIRD_API_KEY") ?? "").trim();
  const secret = (Deno.env.get("SEND_SMS_HOOK_SECRETS") ?? "")
    .trim()
    .replace("v1,whsec_", "");
  const region = /^bk_([a-z]{2}\d+)_[A-Za-z0-9_-]+$/.exec(apiKey);

  if (!region || !secret) {
    return failure(500, "Set BIRD_API_KEY and SEND_SMS_HOOK_SECRETS for this function.");
  }

  const payload = await req.text();
  let event: any;
  try {
    event = new Webhook(secret).verify(payload, Object.fromEntries(req.headers));
  } catch {
    return failure(401, "The hook signature is not valid.");
  }

  const phone = String(event?.sms?.phone ?? event?.user?.phone ?? "")
    .replace(/^\+/, "");
  const code = String(event?.sms?.otp ?? "");

  if (!/^[1-9]\d{1,14}$/.test(phone) || !/^\d{4,8}$/.test(code)) {
    return failure(400, "The hook payload needs a phone number and a code of 4 to 8 digits.");
  }

  const request = {
    method: "POST",
    redirect: "error" as RequestRedirect,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `supabase-otp/${await hmacHex(secret, payload)}`,
    },
    body: JSON.stringify({
      to: `+${phone}`,
      template: { slug: "bird_otp_verification", parameters: { code } },
    }),
  };

  const deadline = Date.now() + 4500;
  let status = 0;
  for (let attempt = 0; attempt < 4 && Date.now() < deadline; attempt++) {
    if (attempt > 0) await wait(Math.min(400, deadline - Date.now()));
    try {
      const response = await fetch(
        `https://${region[1]}.platform.bird.com/v1/sms/messages`,
        {
          ...request,
          signal: AbortSignal.timeout(Math.max(1, Math.min(2000, deadline - Date.now()))),
        },
      );
      await response.body?.cancel();
      status = response.status;
    } catch {
      status = 0;
    }
    if (status === 202) return json();
    if (status !== 0 && status !== 409) break;
  }

  if (status === 0 || status === 409) {
    return failure(503, "Bird did not confirm the message in time. It may still be sent.");
  }
  return failure(status >= 500 ? 503 : 500, `Bird returned HTTP ${status}.`);
});
