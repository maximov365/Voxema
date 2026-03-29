# Discovery: FEAT-3 — Backend Technology Stack

**Mode:** Combined Technical + Market & Competitive Discovery
**Date:** 2026-03-29

---

## Discovery Question

What language, framework, hosting platform, database, and architecture should Voxema use for its post-MVP backend services (authentication, subscription/billing, LLM proxy, usage tracking, admin dashboard)?

The backend is **content-stateless** — it never stores audio, transcripts, or summaries. It stores only: user accounts, subscription status, usage counters, and rate limit configuration.

---

## Prior Decisions

- **DEC-1:** Lemon Squeezy as merchant of record; subscription-only Pro ($12/mo or $96/yr); JWT-based offline license validation
- **DEC-2:** Hybrid model packaging; bundled Whisper tiny + ECAPA-TDNN; on-demand download for larger models

Both decisions constrain the backend: it must integrate with Lemon Squeezy webhooks and license key API, and it must issue/validate JWTs for offline license checks.

---

## Context

Voxema's backend is architecturally narrow but operationally critical for the Pro tier:

1. **Few endpoints, high reliability** — auth, billing webhooks, LLM proxy, usage tracking. Roughly 10–15 API routes total.
2. **Content-stateless** — no transcript storage, no audio. Only metadata and usage counters. This dramatically simplifies the data layer.
3. **LLM proxy is the hot path** — the only latency-sensitive and cost-sensitive endpoint. It receives text transcripts, applies server-side prompts, forwards to Anthropic/OpenAI, and streams the response back.
4. **Solo developer / tiny team** — operational simplicity and development velocity matter more than raw performance.
5. **Offline-first client** — the backend must support JWT offline validation; client must function when backend is unreachable.
6. **Privacy constraints** — server logs must not contain transcript text; TLS required; no persistent transcript storage.

---

## Market & Competitive Research

### Reference 1 — Superwhisper

- **What they do:** Local Whisper-based dictation/transcription for macOS with Pro tier cloud features
- **Backend approach:** Small backend for license validation and cloud model access. Uses Lemon Squeezy for payments (same as Voxema DEC-1). Likely a lightweight Node.js or similar backend.
- **Strengths:** Minimal backend surface area; license key + cloud model proxy is the entire backend scope
- **Weaknesses:** No public documentation on backend architecture
- **URL:** https://superwhisper.com

### Reference 2 — Krisp

- **What they do:** On-device noise cancellation + meeting transcription with cloud AI features
- **Backend approach:** Backend handles authentication, subscription management, and cloud AI processing. Multi-tier pricing. Larger team, more complex infrastructure.
- **Strengths:** Proven model of local processing + cloud AI proxy for premium users
- **Weaknesses:** Enterprise-scale infrastructure; not representative of indie developer constraints
- **URL:** https://krisp.ai

### Reference 3 — Typefully / Cal.com / Plausible (indie SaaS references)

- **Typefully:** TypeScript backend (Next.js API routes), hosted on Vercel. Small team, simple API surface.
- **Cal.com:** TypeScript monorepo (Next.js + tRPC), self-hostable, Postgres backend. Open-source.
- **Plausible:** Elixir backend, self-hostable, Postgres + ClickHouse. Open-source analytics.
- **Pattern:** Successful indie SaaS products overwhelmingly use TypeScript/Node.js or Go for backends, PostgreSQL for data, and Railway/Fly.io/Vercel for hosting.

### Reference 4 — LiteLLM (LLM proxy reference)

- **What they do:** Open-source LLM proxy that provides a unified API across 100+ LLM providers
- **Architecture:** Python (FastAPI), supports streaming, per-user rate limiting, token tracking, model fallback, spend management
- **Strengths:** Proven LLM proxy patterns; demonstrates that per-user token tracking and provider fallback are solved problems
- **Weaknesses:** Designed as a general-purpose proxy, not a product backend; too heavy for Voxema's needs
- **URL:** https://github.com/BerriAI/litellm

### Patterns Observed

1. **Indie SaaS backends are small** — 10–30 API routes, single-digit services, PostgreSQL as primary store
2. **TypeScript dominates indie SaaS** — lowest friction for solo developers who already know JavaScript; Go is the alternative for performance-sensitive paths
3. **LLM proxy is a thin layer** — receive request, validate auth, apply prompt template, forward to provider, stream response back, log usage
4. **Lemon Squeezy integration is TypeScript-first** — official SDK, webhook libraries, and community examples are overwhelmingly JavaScript/TypeScript
5. **Railway is the default for indie SaaS** — simple deploy, managed Postgres, usage-based pricing; Fly.io for global edge needs

---

## Area 1: Language & Framework

### Options Considered

1. **Go** (Chi or Echo)
2. **TypeScript** (Node.js with Hono)
3. **Swift** (Vapor)
4. **Python** (FastAPI)
5. **Rust** (Axum)

### Pre-filter: Architecture Compliance

All five options can implement a content-stateless REST API with JWT validation, HTTP client for LLM proxy, and webhook handling. None violates architecture guardrails. All proceed to comparison.

### Comparison

#### Option 1 — Go (Chi)

- **Pros:** Single binary deployment; excellent HTTP stdlib; strong concurrency model (goroutines); fast cold start; small memory footprint; good JWT libraries (golang-jwt); good HTTP client for LLM proxy; built-in streaming support
- **Cons:** Slightly more verbose than TypeScript for CRUD; smaller Lemon Squeezy ecosystem (no official SDK); error handling verbosity; less familiar to typical macOS/iOS developer
- **Dependency friendliness:** Excellent — Go modules, minimal transitive dependencies, Chi is ~5 files
- **Implementation simplicity:** High for the LLM proxy; medium for webhook integration (manual HMAC verification)
- **Operational simplicity:** High — single binary, no runtime, ~10MB container image
- **Value-to-complexity:** High
- **Reversibility:** Easy — standard REST API; any language can replace it
- **Pipeline fit:** Fits cleanly — no impact on client pipeline
- **MVP fit:** Good — fast to deploy, easy to operate
- **Long-term fit:** Excellent — scales well, low operational burden
- **Developer velocity:** Medium — fast for experienced Go developers, slower initial velocity if learning Go
- **Ecosystem maturity for tasks:** Good JWT libraries (golang-jwt), HTTP clients, Apple Sign In libraries exist (go-signin-with-apple); no official Lemon Squeezy SDK
- **Deployment simplicity:** Excellent — single static binary, tiny Docker image
- **Hiring/contributor friendliness:** Good — Go is widely known, but Voxema's primary language is Swift

#### Option 2 — TypeScript (Node.js with Hono)

- **Pros:** Fastest development velocity for small APIs; Hono is ultralight (~14kb), runs on Node.js/Bun/edge; excellent Lemon Squeezy ecosystem (official SDK, typed webhook library `lemonsqueezy-webhooks`); rich npm ecosystem for JWT (jose), Apple Sign In validation, HTTP streaming; Zod for runtime validation; familiar to web developers
- **Cons:** Runtime dependency (Node.js); slightly higher memory than Go; type safety is compile-time only (needs Zod for runtime); npm dependency tree can be deep
- **Dependency friendliness:** Good — npm is mature but dependency trees can be large; Hono itself is minimal
- **Implementation simplicity:** High — richest ecosystem for all five backend tasks (auth, billing webhooks, LLM proxy, usage tracking, admin)
- **Operational simplicity:** High — well-understood deployment patterns, first-class Railway/Fly.io/Vercel support
- **Value-to-complexity:** High
- **Reversibility:** Easy — standard REST API; any language can replace it
- **Pipeline fit:** Fits cleanly — no impact on client pipeline
- **MVP fit:** Excellent — fastest path to working backend; Lemon Squeezy integration is nearly turnkey
- **Long-term fit:** Good — adequate performance, but may need optimization at scale
- **Developer velocity:** Highest of all options — richest ecosystem, most examples, fastest iteration
- **Ecosystem maturity for tasks:** Excellent — official Lemon Squeezy SDK, typed webhook handlers, `jose` for JWT, Apple auth libraries, streaming HTTP clients for LLM proxy, Drizzle/Prisma for DB
- **Deployment simplicity:** Good — Dockerfile or buildpack; first-class support on all major PaaS
- **Hiring/contributor friendliness:** Excellent — TypeScript is the most widely known backend language

#### Option 3 — Swift (Vapor)

- **Pros:** Same language as macOS client (shared knowledge, potentially shared types); strong type system; modern async/await; production-proven (Things Cloud, Apple services); Vapor 5 with JWTKit, built-in middleware
- **Cons:** Smallest server ecosystem of all options; no Lemon Squeezy SDK or webhook library; limited community examples for webhook-heavy backends; Docker images are large (~200MB+); fewer hosting platform integrations; debugging server Swift is less mature
- **Dependency friendliness:** Medium — Swift Package Manager is clean but the ecosystem is thin
- **Implementation simplicity:** Medium — good fundamentals, but must build Lemon Squeezy integration from scratch
- **Operational simplicity:** Medium — larger Docker images, fewer PaaS integrations, less community knowledge
- **Value-to-complexity:** Medium
- **Reversibility:** Easy — standard REST API
- **Pipeline fit:** Fits cleanly — no impact on client pipeline
- **MVP fit:** Medium — same language is appealing but ecosystem gaps slow initial development
- **Long-term fit:** Good — if Swift server ecosystem continues to grow
- **Developer velocity:** Medium — fast for Swift developers, but ecosystem gaps for Lemon Squeezy and LLM provider integrations require manual implementation
- **Ecosystem maturity for tasks:** Weak for billing/webhook integration; adequate for JWT and auth; Apple Sign In is native
- **Deployment simplicity:** Medium — Docker works but images are larger; fewer one-click deploy options
- **Hiring/contributor friendliness:** Low for server development — Swift server developers are rare

#### Option 4 — Python (FastAPI)

- **Pros:** AI/ML ecosystem alignment; FastAPI has excellent developer experience; rich LLM library ecosystem (litellm, langchain); strong typing with Pydantic; good async support
- **Cons:** Slowest runtime performance of all options; GIL limitations for concurrent requests; larger deployment footprint; dependency management (pip/poetry) is less reliable than Go modules or npm; not the project's primary language
- **Dependency friendliness:** Medium — pip dependencies can conflict; virtual environments required
- **Implementation simplicity:** High for LLM proxy; medium for the rest
- **Operational simplicity:** Medium — requires Python runtime, dependency management
- **Value-to-complexity:** Medium
- **Reversibility:** Easy — standard REST API
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Medium — fast for LLM proxy, adequate for the rest
- **Long-term fit:** Medium — performance ceiling, dependency management overhead
- **Developer velocity:** High for LLM-related features; medium overall
- **Ecosystem maturity for tasks:** Good for LLM proxy; adequate for JWT/auth; weak for Lemon Squeezy (no official SDK)
- **Deployment simplicity:** Medium — Docker required, larger images
- **Hiring/contributor friendliness:** Good — Python is widely known

#### Option 5 — Rust (Axum)

- **Pros:** Best performance; memory safety; excellent type system; small binaries
- **Cons:** Highest development cost for simple CRUD; steep learning curve; slowest iteration speed; no Lemon Squeezy ecosystem; compile times slow development cycle
- **Dependency friendliness:** Good — Cargo is excellent, but compile times are high
- **Implementation simplicity:** Low — ownership system adds friction for simple web endpoints
- **Operational simplicity:** High — single binary, tiny footprint (similar to Go)
- **Value-to-complexity:** Low — performance is wasted on a low-traffic CRUD API
- **Reversibility:** Easy — standard REST API
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Poor — development velocity too low for the simplicity of the task
- **Long-term fit:** Good if performance ever matters (unlikely for this backend)
- **Developer velocity:** Lowest of all options
- **Ecosystem maturity for tasks:** Adequate but thin for all five backend tasks
- **Deployment simplicity:** Excellent — single static binary
- **Hiring/contributor friendliness:** Low — smallest talent pool for web backends

### Decision Quality Score — Language & Framework

Scoring: 1 = poor, 3 = acceptable, 5 = strong

| Criterion | Go (Chi) | TypeScript (Hono) | Swift (Vapor) | Python (FastAPI) | Rust (Axum) |
|---|---|---|---|---|---|
| MVP fit | 4 | 5 | 3 | 3 | 2 |
| Architecture fit | 5 | 5 | 5 | 4 | 5 |
| Implementation simplicity | 4 | 5 | 3 | 4 | 2 |
| Reversibility | 5 | 5 | 5 | 5 | 5 |
| Dependency friendliness | 5 | 4 | 3 | 3 | 4 |
| Operational simplicity | 5 | 4 | 3 | 3 | 5 |
| Testability | 4 | 5 | 4 | 4 | 4 |
| Long-term fit | 5 | 4 | 4 | 3 | 4 |
| **Total** | **37** | **37** | **30** | **29** | **31** |

### Recommendation — Language & Framework

**TypeScript with Hono on Node.js.**

Go and TypeScript score identically at 37/40, but TypeScript wins on the tiebreaker: **Lemon Squeezy ecosystem**. The official Lemon Squeezy JavaScript SDK, typed webhook handler (`lemonsqueezy-webhooks`), and abundant community examples for JWT offline validation, Apple Sign In, and LLM provider streaming make TypeScript the fastest path to a working backend. For a solo developer where development velocity is the primary constraint, this ecosystem advantage is decisive.

Hono specifically over Fastify or Express because: ultralight (~14kb), built-in JWT/CORS/rate-limiting middleware, runs on Node.js today with option to deploy to edge runtimes later, and excellent TypeScript inference.

**Decision stability:** Stable. The backend is a thin REST API — if TypeScript proves insufficient (unlikely for this scale), migration to Go is straightforward since the API surface is small and well-defined.

---

## Area 2: Hosting & Infrastructure

### Options Considered

1. **Railway**
2. **Fly.io**
3. **Hetzner + Docker Compose**
4. **AWS (ECS/Fargate + RDS)**
5. **Vercel** (serverless)

### Pre-filter: Architecture Compliance

All options can host a content-stateless Node.js backend with PostgreSQL. Vercel's serverless model has constraints for streaming LLM responses (function timeout limits) that may require workarounds. All proceed to comparison.

### Comparison

#### Option 1 — Railway

- **Pros:** Simplest deployment for indie SaaS; usage-based pricing ($5/mo Hobby, $20/mo Pro); one-click managed Postgres; auto-deploy from GitHub; visual project canvas; built-in cron jobs for usage aggregation; Nixpacks auto-detects Node.js; managed Redis available if needed later
- **Cons:** No edge deployment (single region per service); smaller company (bus factor risk); less mature than AWS; no built-in DDoS protection beyond Cloudflare proxy
- **Dependency friendliness:** N/A (hosting)
- **Implementation simplicity:** Highest — push to deploy, no Dockerfile required
- **Operational simplicity:** High
- **Value-to-complexity:** High
- **Reversibility:** Easy — Docker container runs anywhere; Postgres is standard
- **Pipeline fit:** Fits cleanly — backend is separate from client pipeline
- **MVP fit:** Excellent — fastest time to production
- **Long-term fit:** Good until ~10K users; may need migration for global latency or compliance
- **Cost at 100 Pro users:** ~$15–25/mo (app + Postgres, minimal traffic)
- **Cost at 1K Pro users:** ~$40–80/mo
- **Cost at 10K Pro users:** ~$150–300/mo (depends on LLM proxy traffic patterns)
- **Data residency:** US regions; limited regional options
- **Vendor lock-in:** Low — standard Docker + Postgres

#### Option 2 — Fly.io

- **Pros:** 35+ global regions (edge deployment); managed Postgres; Machines API for fine-grained scaling; scale-to-zero; competitive pricing; good for latency-sensitive LLM proxy if users are global
- **Cons:** Steeper learning curve (fly.toml, flyctl); managed Postgres starts at $38/mo (Basic plan); more operational complexity than Railway; occasional reliability complaints; requires understanding Machines API
- **Dependency friendliness:** N/A
- **Implementation simplicity:** Medium — requires fly.toml config, Docker understanding
- **Operational simplicity:** Medium — more knobs to configure
- **Value-to-complexity:** Medium
- **Reversibility:** Easy — Docker + Postgres
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Medium — unnecessary complexity for a single-region backend at launch
- **Long-term fit:** Excellent — when global latency matters
- **Cost at 100 Pro users:** ~$45–55/mo (app VM + managed Postgres Basic at $38)
- **Cost at 1K Pro users:** ~$60–100/mo
- **Cost at 10K Pro users:** ~$150–350/mo
- **Data residency:** Extensive regional options (EU, APAC, Americas)
- **Vendor lock-in:** Low — Docker + Postgres

#### Option 3 — Hetzner + Docker Compose

- **Pros:** Cheapest option by far (CX23: €3.99/mo for 2 vCPU, 4GB RAM); full control; EU data residency (Germany/Finland); no platform abstraction; predictable costs
- **Cons:** Highest operational burden — must manage OS updates, backups, SSL certificates, monitoring, database backups, security patches; no auto-scaling; no managed Postgres (run your own); single point of failure unless you set up redundancy
- **Dependency friendliness:** N/A
- **Implementation simplicity:** Low — must set up everything manually
- **Operational simplicity:** Low — full ops burden on solo developer
- **Value-to-complexity:** Low for a solo developer (cheap but time-expensive)
- **Reversibility:** Easy — Docker + Postgres
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Poor — too much ops overhead for a solo developer at launch
- **Long-term fit:** Good for cost optimization once product is stable and ops is automated
- **Cost at 100 Pro users:** ~€5–8/mo
- **Cost at 1K Pro users:** ~€8–15/mo
- **Cost at 10K Pro users:** ~€15–40/mo
- **Data residency:** EU (Germany, Finland); also US, Singapore
- **Vendor lock-in:** None

#### Option 4 — AWS (ECS/Fargate + RDS)

- **Pros:** Most flexible; best compliance story; extensive services; auto-scaling; multi-region; RDS managed Postgres
- **Cons:** Highest complexity; steep learning curve; cost unpredictability (RDS minimum ~$15/mo, Fargate billing complexity); overkill for 10–15 API routes; requires IAM, VPC, security group configuration
- **Dependency friendliness:** N/A
- **Implementation simplicity:** Low — significant infrastructure setup
- **Operational simplicity:** Low — many moving parts, complex billing
- **Value-to-complexity:** Low for a solo developer (flexibility is wasted at this scale)
- **Reversibility:** Medium — some AWS-specific configuration (ALB, security groups, IAM)
- **Pipeline fit:** Fits cleanly
- **MVP fit:** Poor — too much overhead
- **Long-term fit:** Excellent for Enterprise tier requirements
- **Cost at 100 Pro users:** ~$50–80/mo (RDS + Fargate + ALB + data transfer)
- **Cost at 1K Pro users:** ~$100–200/mo
- **Cost at 10K Pro users:** ~$300–600/mo
- **Data residency:** Global (any AWS region)
- **Vendor lock-in:** Medium — AWS-specific IAM, ALB, CloudWatch, etc.

#### Option 5 — Vercel (Serverless)

- **Pros:** Zero ops for Node.js; automatic scaling; excellent DX for TypeScript; free tier generous for low traffic; built-in edge network
- **Cons:** Serverless function timeout (default 10s, max 300s on Pro) may constrain LLM proxy streaming for long transcripts; cold starts add latency; no managed Postgres (need external like Neon or Supabase); less control over runtime; pricing can spike unpredictably at scale
- **Dependency friendliness:** N/A
- **Implementation simplicity:** High for simple APIs; medium for streaming LLM proxy
- **Operational simplicity:** High — fully managed
- **Value-to-complexity:** Medium — function timeouts are a real constraint for LLM proxy
- **Reversibility:** Medium — serverless function structure may need refactoring for traditional deployment
- **Pipeline fit:** Requires adaptation — streaming LLM responses through serverless functions has timeout constraints
- **MVP fit:** Medium — function timeout risk for LLM proxy is a blocking concern
- **Long-term fit:** Medium — cost unpredictability and streaming constraints
- **Cost at 100 Pro users:** ~$20–30/mo (Pro plan + external Postgres)
- **Cost at 1K Pro users:** ~$40–100/mo
- **Cost at 10K Pro users:** ~$200–500/mo (function invocation costs)
- **Data residency:** US-centric (Vercel); Postgres depends on external provider
- **Vendor lock-in:** Medium — serverless function structure

### Decision Quality Score — Hosting

| Criterion | Railway | Fly.io | Hetzner+Docker | AWS | Vercel |
|---|---|---|---|---|---|
| MVP fit | 5 | 3 | 2 | 2 | 3 |
| Architecture fit | 5 | 5 | 5 | 5 | 3 |
| Implementation simplicity | 5 | 3 | 2 | 2 | 4 |
| Reversibility | 5 | 5 | 5 | 4 | 3 |
| Dependency friendliness | 5 | 5 | 5 | 3 | 3 |
| Operational simplicity | 5 | 3 | 1 | 2 | 5 |
| Testability | 4 | 4 | 4 | 4 | 3 |
| Long-term fit | 4 | 5 | 4 | 5 | 3 |
| **Total** | **38** | **33** | **28** | **27** | **27** |

### Recommendation — Hosting

**Railway** for initial deployment. Migrate to Fly.io or Hetzner if/when global latency, data residency, or cost optimization becomes a priority.

Railway scores 38/40 — highest across all criteria. For a solo developer launching a backend with ~10–15 API routes and managed Postgres, Railway is the simplest viable choice. Push-to-deploy from GitHub, one-click Postgres, usage-based pricing, and no Dockerfile required.

**Decision stability:** Temporary — revisit after 1K Pro users or when EU data residency is required. Migration is straightforward since the backend is a Docker container with standard Postgres.

---

## Area 3: Database

### Options Considered

1. **PostgreSQL** (managed, on Railway)
2. **SQLite** (on server filesystem)

### Comparison

#### Option 1 — PostgreSQL (managed)

- **Pros:** Concurrent access from multiple connections; managed backups on Railway; ACID transactions for usage counter updates; rich query capabilities for admin dashboard; standard migration tooling (Drizzle ORM migrations); connection pooling; battle-tested for web backends
- **Cons:** Slight additional cost (~$5–10/mo on Railway); requires ORM or query builder setup
- **Reversibility:** Easy — standard SQL; can migrate to any Postgres host
- **MVP fit:** Excellent — managed Postgres on Railway is zero-config

#### Option 2 — SQLite (server-side)

- **Pros:** Zero additional cost; zero setup; file-based; same technology as the macOS client; good for read-heavy workloads
- **Cons:** Single-writer limitation — concurrent usage counter updates from multiple LLM proxy requests will serialize; no managed backups (must implement); no connection pooling; harder to query from admin dashboard; less suitable for multi-instance deployment if scaling horizontally
- **Reversibility:** Medium — migration to Postgres needed if scaling requires it
- **MVP fit:** Adequate but risky — single-writer becomes a bottleneck with concurrent LLM proxy requests

### Decision Quality Score — Database

| Criterion | PostgreSQL | SQLite |
|---|---|---|
| MVP fit | 5 | 3 |
| Architecture fit | 5 | 4 |
| Implementation simplicity | 4 | 5 |
| Reversibility | 5 | 3 |
| Dependency friendliness | 4 | 5 |
| Operational simplicity | 5 | 3 |
| Testability | 5 | 4 |
| Long-term fit | 5 | 2 |
| **Total** | **38** | **29** |

### Recommendation — Database

**PostgreSQL (managed on Railway).**

The backend handles concurrent LLM proxy requests that update usage counters atomically. PostgreSQL's concurrent write support, managed backups, and admin dashboard query capabilities make it clearly superior for this use case. The client uses SQLite locally (per architecture) — the backend uses PostgreSQL. This is standard industry practice: different data access patterns warrant different databases.

**Schema outline:**

```
users (id, apple_id, email, created_at, updated_at)
subscriptions (id, user_id, lemon_squeezy_subscription_id, status, plan, license_key, jwt_payload, expires_at, created_at, updated_at)
usage_counters (id, user_id, period_start, period_end, requests_count, input_tokens, output_tokens, estimated_cost_cents)
rate_limits (id, plan, max_requests_per_day, max_tokens_per_day, max_requests_per_minute)
```

Four tables. The entire backend data model fits in one migration file.

**ORM:** Drizzle ORM — lightweight, TypeScript-native, schema-as-code, generates migrations, works well with Hono.

**Decision stability:** Stable.

---

## Area 4: LLM Proxy Architecture

### Design Decisions

#### 4.1 Direct Passthrough vs. Prompt-Wrapping Proxy

**Recommendation: Prompt-wrapping proxy.**

The PRD explicitly states: "Backend applies optimized server-side prompts" and "Server-side prompt management — optimized prompts for meeting summarization maintained and iterated on the backend, deployed independently of app releases."

The proxy is not a dumb passthrough — it:
1. Receives the diarized transcript text from the client
2. Applies a server-side prompt template (stored in the backend, versioned independently of the app)
3. Forwards the assembled prompt to the LLM provider
4. Streams the structured response back to the client

This enables prompt iteration without app updates — a key Pro tier differentiator.

#### 4.2 Streaming Responses

**Recommendation: Server-Sent Events (SSE) streaming.**

The LLM provider returns tokens via SSE. The backend proxies these tokens directly to the client as they arrive (zero-buffer streaming). This minimizes Time To First Token (TTFT) and provides a responsive user experience.

Implementation: Hono supports SSE natively. The backend opens a streaming connection to Anthropic/OpenAI, and pipes chunks to the client connection as they arrive.

Token counting happens after the stream completes — the provider's `usage` field in the final SSE message contains actual token counts.

#### 4.3 Rate Limiting Per User

**Recommendation: Database-backed rate limiting with in-memory cache.**

Rate limit tiers stored in `rate_limits` table (per plan). Current usage tracked in `usage_counters` table (per user, per billing period). Check flow:

1. Request arrives → check in-memory cache for user's current usage
2. If cache miss → query `usage_counters` table
3. If within limits → forward to LLM provider
4. After response completes → update `usage_counters` with actual token count
5. If over limit → return 429 with `x-ratelimit-remaining` and `x-ratelimit-reset` headers

For a single-instance deployment (sufficient for 1K–10K users), in-memory rate limiting with periodic DB sync is adequate. No Redis needed initially.

Suggested initial limits (Pro tier):
- 50 requests/day (meetings)
- 500K tokens/day
- 5 requests/minute burst

#### 4.4 Token Counting

**Recommendation: Post-response actual counting only.**

Pre-request estimation is unreliable and adds latency. Instead:
1. Check user's accumulated usage against daily/monthly budget *before* forwarding
2. Forward the request (if within budget)
3. Read actual `usage` from provider response after stream completes
4. Update `usage_counters` with actual tokens consumed

If a request pushes the user over budget, it still completes (the response is already streaming). The *next* request gets rate-limited. This matches the standard LLM proxy pattern.

#### 4.5 Provider Failover

**Recommendation: Anthropic primary, OpenAI fallback. Manual switchover initially.**

For MVP backend:
- Configure primary provider (Anthropic Claude Haiku 4.5) and fallback (OpenAI GPT-4o-mini)
- If primary returns 5xx or times out after 30s → retry once with primary
- If retry fails → attempt fallback provider
- If fallback fails → return error to client; client offers LocalProvider fallback

Provider configuration stored in environment variables. Manual switchover via config change initially; automated health-check-based routing can be added later.

Prompt templates should be provider-agnostic (same structured output schema) with provider-specific formatting handled at the proxy layer.

#### 4.6 Cost Allocation Per User

**Recommendation: Track actual token usage per user per billing period.**

Each LLM proxy response includes actual token counts from the provider. Store:
- `input_tokens` (transcript + prompt template)
- `output_tokens` (summary response)
- `estimated_cost_cents` (calculated from provider's per-token pricing at time of request)

This enables:
- Per-user cost visibility in admin dashboard
- Cost-based rate limiting if needed
- Margin analysis per user

**Decision stability:** Stable for the passthrough-with-prompt-wrapping pattern. Rate limit values are temporary — tune after real usage data.

---

## Area 5: Authentication Flow

### 5.1 Apple Sign In (Server-Side)

**Flow:**
1. macOS client initiates Apple Sign In via `AuthenticationServices` framework
2. Client receives an `identityToken` (JWT) and `authorizationCode` from Apple
3. Client sends `authorizationCode` to Voxema backend `/auth/apple` endpoint
4. Backend exchanges `authorizationCode` with Apple's token endpoint (`https://appleid.apple.com/auth/token`) to get `id_token` and `refresh_token`
5. Backend validates `id_token`: verify JWS signature against Apple's public keys, check `iss`, `aud`, `exp`
6. Backend creates or updates user record; returns Voxema session JWT

**Library:** `apple-signin-auth` npm package (or manual JWT validation with `jose` library).

### 5.2 Email-Based Magic Link (No Passwords)

**Flow:**
1. User enters email on client
2. Client sends email to backend `/auth/email/request`
3. Backend generates a time-limited token (6-digit OTP or magic link URL), stores hash in DB, sends email
4. User enters OTP (or clicks link) → client sends to backend `/auth/email/verify`
5. Backend validates token → creates/updates user → returns Voxema session JWT

**Email delivery:** Use a transactional email service (Resend or Postmark — both have generous free tiers: Resend 3K/mo, Postmark 100/mo free).

OTP is recommended over magic link for a macOS app because magic links open in a browser, requiring a custom URL scheme callback to return to the app. OTP keeps the user in the app.

### 5.3 JWT Token Lifecycle

**Design:**
- **Access token:** Short-lived (15 minutes), used for API requests
- **Refresh token:** Long-lived (30 days), stored in macOS Keychain, used to obtain new access tokens
- **License token:** Special JWT with embedded subscription status, signed with Voxema's private key, validated offline by the client using the embedded public key. Refreshed every 7 days when online (per PRD). Contains: `user_id`, `plan`, `features`, `expires_at`

**Offline validation:** The license token is the critical JWT for offline-first behavior. The client validates it locally (signature check + expiry check). If expired and offline → grace period (e.g., 7 additional days). If grace period exceeded → degrade to Free tier features.

### 5.4 Lemon Squeezy Integration

**Flow:**
1. User purchases Pro subscription on voxema.com (Lemon Squeezy checkout)
2. During checkout, user provides their Voxema account email (or Apple ID)
3. Lemon Squeezy sends webhook to backend: `subscription_created`, `subscription_updated`, `subscription_cancelled`, etc.
4. Backend verifies webhook signature (HMAC-SHA256)
5. Backend matches subscription to user by email
6. Backend updates `subscriptions` table and generates new license JWT
7. On next client → backend sync, client receives updated license JWT

**Webhook events to handle:**
- `subscription_created` → activate Pro
- `subscription_updated` → update plan details
- `subscription_cancelled` → mark subscription ending at period end
- `subscription_expired` → revoke Pro (degrade to Free)
- `subscription_payment_failed` → flag for grace period handling
- `license_key_created` → store license key for backup validation

**Decision stability:** Stable for the overall auth architecture. Email provider choice (Resend vs Postmark) is temporary.

---

## Area 6: Cost Estimation

### LLM API Cost Per Meeting

Assumptions:
- Average meeting transcript: ~5,000 tokens
- Server-side prompt template overhead: ~1,000 tokens
- Total input per request: ~6,000 tokens
- Average output (structured summary): ~1,500 tokens
- Average meetings per Pro user per month: 20

#### Claude Haiku 4.5 (Primary)

| Component | Tokens | Rate | Cost |
|---|---|---|---|
| Input | 6,000 | $1.00/MTok | $0.006 |
| Output | 1,500 | $5.00/MTok | $0.0075 |
| **Per meeting** | | | **$0.0135** |
| **Per user/month (20 meetings)** | | | **$0.27** |

With prompt caching (5-min cache for shared prompt template): input cost drops to ~$0.003 per meeting → **$0.009/meeting**, **$0.18/user/month**.

#### GPT-4o-mini (Fallback)

| Component | Tokens | Rate | Cost |
|---|---|---|---|
| Input | 6,000 | $0.15/MTok | $0.0009 |
| Output | 1,500 | $0.60/MTok | $0.0009 |
| **Per meeting** | | | **$0.0018** |
| **Per user/month (20 meetings)** | | | **$0.036** |

GPT-4o-mini is ~7x cheaper than Claude Haiku 4.5 per meeting. Quality difference needs benchmarking with real meeting transcripts.

### Infrastructure Cost Breakdown

#### At 100 Pro Users

| Component | Monthly Cost |
|---|---|
| Railway (app + Postgres) | ~$15–25 |
| LLM API (Haiku, 100 users × 20 meetings) | ~$27 |
| LLM API (with caching) | ~$18 |
| Transactional email (Resend free tier) | $0 |
| Domain + DNS | ~$1 |
| **Total** | **~$44–53** |

Revenue at 100 Pro users: 100 × $8–12 = **$800–1,200/mo**
Lemon Squeezy fee (5% + $0.50): ~$90–110/mo
**Net margin: ~$640–1,040/mo (~80–87%)**

#### At 1,000 Pro Users

| Component | Monthly Cost |
|---|---|
| Railway (scaled) | ~$40–80 |
| LLM API (Haiku, with caching) | ~$180 |
| Transactional email (Resend paid) | ~$20 |
| Monitoring (basic) | ~$0–10 |
| **Total** | **~$240–290** |

Revenue: 1,000 × $8–12 = **$8,000–12,000/mo**
Lemon Squeezy fee: ~$900–1,100/mo
**Net margin: ~$6,600–10,700/mo (~82–89%)**

#### At 10,000 Pro Users

| Component | Monthly Cost |
|---|---|
| Railway or Fly.io (scaled) | ~$150–300 |
| LLM API (Haiku, with caching) | ~$1,800 |
| Transactional email | ~$50 |
| Monitoring | ~$30 |
| **Total** | **~$2,030–2,180** |

Revenue: 10,000 × $8–12 = **$80,000–120,000/mo**
Lemon Squeezy fee: ~$9,000–11,000/mo
**Net margin: ~$68,800–106,800/mo (~86–89%)**

### Margin Analysis

**Is $12/mo ($8/mo annual) enough margin?**

Yes, by a wide margin. LLM API cost per user is $0.18–0.27/month (the dominant variable cost). Even at the lowest annual price ($8/mo), per-user margin is $7.23–7.32/month (90%+ gross margin on variable costs). Infrastructure costs are essentially fixed up to ~1K users and grow sub-linearly after that.

The pricing risk is not margin — it's conversion. The question is whether $12/mo ($8/mo annual) is competitive enough to convert Free users to Pro, given that Free tier already includes CloudProvider with user's own API key.

**Decision stability:** Stable for margin viability. LLM pricing continues to decrease, so margins will improve over time. GPT-4o-mini as primary (instead of Haiku) would increase margin to ~$7.96/user/month — consider after quality benchmarking.

---

## Recommended Stack Summary

**TypeScript (Hono) on Node.js**, deployed to **Railway** with **managed PostgreSQL**, using **Drizzle ORM** for database access. The LLM proxy uses a **prompt-wrapping architecture** with SSE streaming, **Anthropic Claude Haiku 4.5** as primary provider and **GPT-4o-mini** as fallback. Authentication via **Apple Sign In** (server-side validation) and **email OTP** (no passwords), with **Lemon Squeezy** webhook integration for subscription management. **JWT-based offline license validation** for the macOS client. Estimated backend cost: **$44–53/month at 100 users**, scaling to **~$2,100/month at 10,000 users**, with **86–90% gross margins** at all scales.

This is the simplest viable backend for a solo developer shipping a privacy-first macOS app with a managed cloud LLM proxy. Every component is reversible, uses standard protocols, and avoids vendor lock-in.

---

## Decision Stability Summary

| Decision | Stability | Revisit Trigger |
|---|---|---|
| Language: TypeScript (Hono) | Stable | Only if performance ceiling is hit (unlikely at this scale) |
| Hosting: Railway | Temporary | At 1K+ users, or when EU data residency is required |
| Database: PostgreSQL | Stable | N/A |
| ORM: Drizzle | Stable | N/A |
| LLM primary: Claude Haiku 4.5 | Temporary | After benchmarking with real meeting transcripts; GPT-4o-mini may be sufficient at 7x lower cost |
| LLM fallback: GPT-4o-mini | Stable | N/A |
| Auth: Apple Sign In + Email OTP | Stable | N/A |
| Billing: Lemon Squeezy webhooks | Stable | Locked by DEC-1 |
| Email: Resend | Temporary | Evaluate Postmark if deliverability issues arise |
| Rate limit values | Temporary | Tune after real usage data |

---

## Risks / Trade-offs

1. **Railway single-region** — all backend services run in one region. If users are globally distributed, LLM proxy latency may be noticeable. Mitigation: LLM proxy latency is dominated by LLM provider response time (seconds), not network hop (~100ms). Revisit if user complaints arise.

2. **Railway platform risk** — smaller company than AWS/GCP. Mitigation: backend is a standard Docker container with Postgres; migration to Fly.io or Hetzner is a half-day task.

3. **TypeScript performance ceiling** — Node.js single-threaded event loop. Mitigation: the backend is I/O-bound (proxying HTTP requests, DB queries), not CPU-bound. Node.js excels at this pattern. At extreme scale (unlikely), add worker threads or migrate hot path to Go.

4. **Lemon Squeezy webhook reliability** — if webhooks fail, subscription state can become stale. Mitigation: implement webhook retry handling; periodic reconciliation job that polls Lemon Squeezy API to verify subscription status.

5. **LLM provider outage** — if both Anthropic and OpenAI are down, Pro cloud summarization fails. Mitigation: client always has LocalProvider fallback per offline-first architecture.

6. **Prompt template versioning** — server-side prompts need a versioning strategy to avoid breaking changes. Mitigation: version prompts explicitly; test new versions against a benchmark set before deployment.

7. **Email OTP deliverability** — transactional emails can land in spam. Mitigation: use a reputable provider (Resend), configure SPF/DKIM/DMARC, and support Apple Sign In as the primary auth method.

---

## Follow-up Implications

1. **Backend repository structure** — decide whether backend lives in the same repo as the macOS client (monorepo) or a separate repo. Recommendation: separate repo for deployment simplicity.
2. **Prompt template storage** — define format and versioning for server-side prompt templates.
3. **Admin dashboard approach** — evaluate: custom (Hono + HTMX or React), vs. off-the-shelf (Retool, AdminJS). Discovery needed.
4. **Monitoring & alerting** — define observability stack for the backend (structured logging, error tracking, uptime monitoring).
5. **CI/CD pipeline** — define deployment pipeline for the backend (GitHub Actions → Railway auto-deploy).
6. **License JWT key management** — define key generation, rotation, and public key distribution to clients.
7. **Server-side prompt template format** — define the schema for prompt templates that enables provider-agnostic prompts with provider-specific formatting.

---

## Should This Go Into DECISIONS.md?

**Yes — record after implementation confirms the choice.** The stack recommendation is clear and well-supported, but the decision should be formalized as DEC-3 after the Architect plan is accepted and before Builder begins. This allows the Architect to validate the stack against implementation details and flag any issues before the decision is locked.

---

## Assumptions Made

1. Backend traffic is dominated by LLM proxy requests (~20 per user per month). Auth and billing endpoints are low-traffic.
2. A single Railway instance (1 vCPU, 1GB RAM) can handle 1K concurrent Pro users based on the I/O-bound nature of the workload.
3. Claude Haiku 4.5 provides sufficient meeting summary quality. Quality benchmarking with real transcripts has not been done.
4. Lemon Squeezy's webhook delivery is reliable enough that periodic reconciliation (not real-time) is sufficient for subscription state consistency.
5. EU data residency is not required at launch (revisit before Enterprise tier).
6. The admin dashboard is a simple internal tool — no customer-facing analytics.

---

## Recommended Next Step

Product should update `docs/PRD.md` Technical Constraints to reflect the backend technology stack (TypeScript/Hono, Railway, PostgreSQL) and create implementation-ready task breakdowns for the backend services.

---

```json
{
  "handoff": {
    "agent": "Discovery",
    "artifact_type": "design_note",
    "artifact_path": "docs/discoveries/FEAT-3-backend-stack.md",
    "status": "produced",
    "next_recommended_agent": "Product",
    "next_recommended_reason": "Discovery complete; update PRD Technical Constraints with backend technology stack decisions.",
    "blocking_issues": [],
    "workflow_state": {
      "task_id": "FEAT-3",
      "artifact_id": null,
      "current_stage": "discovery",
      "quality_loop_iteration": 0,
      "builder_cycle_count": 0,
      "analytics_used": false,
      "product_spec_accepted": false
    }
  }
}
```
