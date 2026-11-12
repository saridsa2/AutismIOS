// Run once in the official self-hosted/v0.8.1 docker directory.
// Secrets stay on the server. Refuse to overwrite an initialized instance.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomBytes, createHmac } from 'node:crypto';
if (existsSync('.env')) throw new Error('An environment already exists; refusing to rotate live secrets.');
const hex = bytes => randomBytes(bytes).toString('hex');
const secret = hex(32);
const jwt = role => {
 const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
 const now = Math.floor(Date.now() / 1000);
 const payload = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ role, iss: 'supabase', iat: now, exp: now + 5 * 365 * 86400 })}`;
 return `${payload}.${createHmac('sha256', secret).update(payload).digest('base64url')}`;
};
const settings = {
 POSTGRES_PASSWORD: hex(32), JWT_SECRET: secret, ANON_KEY: jwt('anon'), SERVICE_ROLE_KEY: jwt('service_role'),
 DASHBOARD_USERNAME: 'littlecompany', DASHBOARD_PASSWORD: hex(24),
 SECRET_KEY_BASE: hex(48), REALTIME_DB_ENC_KEY: hex(8), VAULT_ENC_KEY: hex(16), PG_META_CRYPTO_KEY: hex(32),
 LOGFLARE_PUBLIC_ACCESS_TOKEN: hex(24), LOGFLARE_PRIVATE_ACCESS_TOKEN: hex(24),
 S3_PROTOCOL_ACCESS_KEY_ID: hex(16), S3_PROTOCOL_ACCESS_KEY_SECRET: hex(32), MINIO_ROOT_PASSWORD: hex(24),
 STUDIO_DEFAULT_ORGANIZATION: 'Little Company', STUDIO_DEFAULT_PROJECT: 'Little Company',
 POOLER_TENANT_ID: 'little-company', STORAGE_TENANT_ID: 'little-company',
 SUPABASE_PUBLIC_URL: 'http://localhost:8002', API_EXTERNAL_URL: 'http://localhost:8002/auth/v1',
 SITE_URL: 'http://localhost:8002', OPENAI_API_KEY: '',
 // Provision caregiver accounts administratively until email delivery is configured.
 DISABLE_SIGNUP: 'true', ENABLE_PHONE_SIGNUP: 'false', ENABLE_PHONE_AUTOCONFIRM: 'false',
 SMTP_HOST: '', SMTP_USER: '', SMTP_PASS: '', SMTP_ADMIN_EMAIL: '', SMTP_SENDER_NAME: 'Little Company',
 FUNCTIONS_VERIFY_JWT: 'true', POOLER_DEFAULT_POOL_SIZE: '10',
};
let env = readFileSync('.env.example', 'utf8');
for (const [key, value] of Object.entries(settings)) {
 const pattern = new RegExp(`^${key}=.*$`, 'm');
 if (!pattern.test(env)) throw new Error(`Missing template key ${key}`);
 env = env.replace(pattern, `${key}=${value}`);
}
writeFileSync('.env', env, { mode: 0o600, flag: 'wx' });
let compose = readFileSync('docker-compose.yml', 'utf8')
 .replace(/^name: supabase$/m, 'name: little-company-supabase')
 .replace(/container_name: supabase-/g, 'container_name: lc-supabase-')
 .replace('container_name: realtime-dev.supabase-realtime', 'container_name: realtime-dev.lc-supabase-realtime')
 .replace('- ${API_GW_HTTP_PORT:-${KONG_HTTP_PORT:-8000}}:8000/tcp', '- "127.0.0.1:8002:8000/tcp"')
 .replace('- ${POSTGRES_PORT}:5432', '- "127.0.0.1:5434:5432"')
 .replace('- ${POOLER_PROXY_PORT_TRANSACTION}:6543', '- "127.0.0.1:6545:6543"');
writeFileSync('docker-compose.yml', compose);
console.log('Prepared isolated Little Company stack. Secrets written to server .env only.');
