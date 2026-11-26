import Foundation

/// The built in list of services Upline knows how to detect and watch.
/// Users can add or override entries in ~/Library/Application Support/Upline/catalog.json
enum Catalog {
    static var userFileURL: URL { Persistence.directory.appendingPathComponent("catalog.json") }

    /// Built in entries merged with the user's overrides (same id replaces).
    static func load() -> [CatalogEntry] {
        var byID = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.id, $0) })
        if let data = try? Data(contentsOf: userFileURL),
           let extra = try? JSONDecoder().decode([CatalogEntry].self, from: data) {
            for e in extra { byID[e.id] = e }
        }
        return Array(byID.values).sorted { $0.name < $1.name }
    }

    private static func s(
        _ id: String, _ name: String, _ category: ServiceCategory,
        status: String? = nil, probes: [String],
        packages: [String] = [], env: [String] = [], hosts: [String] = [], images: [String] = [],
        auth: AuthCheck? = nil, color: String, feed: String? = nil
    ) -> CatalogEntry {
        var e = CatalogEntry(
            id: id, name: name, category: category, statusPage: status, probes: probes,
            packages: packages, envKeys: env, hosts: hosts, images: images, auth: auth, color: color
        )
        e.statusFeed = feed
        return e
    }

    private static func bearer(_ url: String, _ keys: [String], extra: [String: String]? = nil) -> AuthCheck {
        AuthCheck(url: url, envKeys: keys, extraHeaders: extra)
    }

    static let builtIn: [CatalogEntry] = {
        var a: [CatalogEntry] = []

        // MARK: AI
        a.append(s("anthropic", "Anthropic", .ai, status: "https://status.anthropic.com",
                   probes: ["https://api.anthropic.com"],
                   packages: ["@anthropic-ai/*", "anthropic", "@ai-sdk/anthropic", "@langchain/anthropic", "langchain-anthropic"],
                   env: ["ANTHROPIC_", "CLAUDE_API"], hosts: ["api.anthropic.com"],
                   auth: AuthCheck(url: "https://api.anthropic.com/v1/models", envKeys: ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"],
                                   header: "x-api-key", valuePrefix: "", extraHeaders: ["anthropic-version": "2023-06-01"]),
                   color: "#E08A5F"))
        a.append(s("openai", "OpenAI", .ai, status: "https://status.openai.com",
                   probes: ["https://api.openai.com"],
                   packages: ["openai", "@ai-sdk/openai", "@langchain/openai", "langchain-openai"],
                   env: ["OPENAI_"], hosts: ["api.openai.com"],
                   auth: bearer("https://api.openai.com/v1/models", ["OPENAI_API_KEY"]), color: "#19C37D"))
        a.append(s("moonshot", "Moonshot Kimi", .ai, probes: ["https://api.moonshot.ai"],
                   env: ["MOONSHOT_", "KIMI_"], hosts: ["moonshot.ai", "moonshot.cn"],
                   auth: bearer("https://api.moonshot.ai/v1/models", ["MOONSHOT_API_KEY", "KIMI_API_KEY"]), color: "#7C79FF"))
        a.append(s("gemini", "Google Gemini", .ai, probes: ["https://generativelanguage.googleapis.com"],
                   packages: ["@google/generative-ai", "@google/genai", "google-generativeai", "google-genai", "@ai-sdk/google"],
                   env: ["GEMINI_", "GOOGLE_GENERATIVE_AI", "GOOGLE_AI_"], hosts: ["generativelanguage.googleapis.com"],
                   auth: AuthCheck(url: "https://generativelanguage.googleapis.com/v1beta/models", envKeys: ["GEMINI_API_KEY", "GOOGLE_GENERATIVE_AI_API_KEY", "GOOGLE_API_KEY"],
                                   header: "x-goog-api-key", valuePrefix: ""),
                   color: "#5B9BFF"))
        a.append(s("mistral", "Mistral", .ai, probes: ["https://api.mistral.ai"],
                   packages: ["@mistralai/*", "mistralai", "@ai-sdk/mistral"], env: ["MISTRAL_"], hosts: ["api.mistral.ai"],
                   auth: bearer("https://api.mistral.ai/v1/models", ["MISTRAL_API_KEY"]), color: "#FF7A2F"))
        a.append(s("groq", "Groq", .ai, status: "https://groqstatus.com", probes: ["https://api.groq.com"],
                   packages: ["groq-sdk", "groq", "@ai-sdk/groq"], env: ["GROQ_"], hosts: ["api.groq.com"],
                   auth: bearer("https://api.groq.com/openai/v1/models", ["GROQ_API_KEY"]), color: "#FF6A4D"))
        a.append(s("deepseek", "DeepSeek", .ai, status: "https://status.deepseek.com", probes: ["https://api.deepseek.com"],
                   env: ["DEEPSEEK_"], hosts: ["api.deepseek.com"],
                   auth: bearer("https://api.deepseek.com/models", ["DEEPSEEK_API_KEY"]), color: "#6A85FF"))
        a.append(s("openrouter", "OpenRouter", .ai, status: "https://status.openrouter.ai", probes: ["https://openrouter.ai/api/v1/models"],
                   packages: ["@openrouter/*"], env: ["OPENROUTER_"], hosts: ["openrouter.ai"],
                   auth: bearer("https://openrouter.ai/api/v1/key", ["OPENROUTER_API_KEY"]), color: "#8A8CFF"))
        a.append(s("replicate", "Replicate", .ai, status: "https://www.replicatestatus.com", probes: ["https://api.replicate.com"],
                   packages: ["replicate"], env: ["REPLICATE_"], hosts: ["api.replicate.com"], color: "#FF5A36"))
        a.append(s("huggingface", "Hugging Face", .ai, status: "https://status.huggingface.co", probes: ["https://huggingface.co"],
                   packages: ["@huggingface/*", "huggingface_hub"], env: ["HF_TOKEN", "HUGGINGFACE_", "HF_API"], hosts: ["huggingface.co"],
                   color: "#FFC22E"))
        a.append(s("cohere", "Cohere", .ai, status: "https://status.cohere.com", probes: ["https://api.cohere.com"],
                   packages: ["cohere-ai", "cohere", "@ai-sdk/cohere"], env: ["COHERE_", "CO_API_KEY"], hosts: ["api.cohere.com", "api.cohere.ai"],
                   color: "#58C79A"))
        a.append(s("elevenlabs", "ElevenLabs", .ai, status: "https://status.elevenlabs.io", probes: ["https://api.elevenlabs.io"],
                   packages: ["elevenlabs", "@elevenlabs/*"], env: ["ELEVENLABS_", "ELEVEN_LABS"], hosts: ["api.elevenlabs.io"],
                   color: "#D9D9E3"))
        a.append(s("pinecone", "Pinecone", .database, status: "https://status.pinecone.io", probes: ["https://api.pinecone.io"],
                   packages: ["@pinecone-database/*", "pinecone", "pinecone-client"], env: ["PINECONE_"], hosts: ["pinecone.io"],
                   color: "#6E8BFF"))

        // MARK: Databases
        a.append(s("neon", "Neon", .database, status: "https://neonstatus.com", probes: ["https://console.neon.tech"],
                   packages: ["@neondatabase/*"], env: ["NEON_"], hosts: ["neon.tech"], color: "#00E599",
                   feed: "statusio:6878fc85709daa75be6c7e3c"))
        a.append(s("supabase", "Supabase", .database, status: "https://status.supabase.com", probes: ["https://api.supabase.com"],
                   packages: ["@supabase/*", "supabase"], env: ["SUPABASE_", "NEXT_PUBLIC_SUPABASE", "EXPO_PUBLIC_SUPABASE"],
                   hosts: ["supabase.co", "supabase.com", "pooler.supabase.com"], color: "#3ECF8E"))
        a.append(s("planetscale", "PlanetScale", .database, status: "https://www.planetscalestatus.com", probes: ["https://api.planetscale.com"],
                   packages: ["@planetscale/*"], env: ["PLANETSCALE_"], hosts: ["psdb.cloud", "planetscale.com"], color: "#E8E8F0"))
        a.append(s("mongodb", "MongoDB Atlas", .database, status: "https://status.mongodb.com", probes: ["https://cloud.mongodb.com"],
                   packages: ["mongodb", "mongoose", "pymongo", "motor"], env: ["MONGODB_", "MONGO_"], hosts: ["mongodb.net"],
                   color: "#00ED64"))
        a.append(s("upstash", "Upstash", .database, status: "https://status.upstash.com", probes: ["https://console.upstash.com"],
                   packages: ["@upstash/*", "upstash-redis"], env: ["UPSTASH_", "KV_REST_API"], hosts: ["upstash.io"], color: "#00E9A3"))
        a.append(s("rediscloud", "Redis Cloud", .database, status: "https://status.redis.io", probes: ["https://app.redislabs.com"],
                   hosts: ["redislabs.com", "redis-cloud.com"], color: "#FF5A4A"))
        a.append(s("turso", "Turso", .database, status: "https://status.turso.tech", probes: ["https://api.turso.tech"],
                   packages: ["@libsql/*", "@tursodatabase/*", "libsql-client"], env: ["TURSO_"], hosts: ["turso.io"], color: "#4FF8D2"))
        a.append(s("firebase", "Firebase", .database, probes: ["https://firestore.googleapis.com"],
                   packages: ["firebase", "firebase-admin", "@react-native-firebase/*", "@firebase/*", "Firebase*", "firebase_core"],
                   env: ["FIREBASE_", "NEXT_PUBLIC_FIREBASE", "EXPO_PUBLIC_FIREBASE"], hosts: ["firebaseio.com", "firebaseapp.com"],
                   color: "#FFCA28"))
        a.append(s("convex", "Convex", .database, status: "https://status.convex.dev", probes: ["https://api.convex.dev"],
                   packages: ["convex"], env: ["CONVEX_", "NEXT_PUBLIC_CONVEX"], hosts: ["convex.cloud"], color: "#F3694C"))

        // MARK: Hosting and infrastructure
        a.append(s("vercel", "Vercel", .hosting, status: "https://www.vercel-status.com", probes: ["https://api.vercel.com"],
                   packages: ["vercel", "@vercel/*"], env: ["VERCEL_"], hosts: ["vercel.app", "vercel.com"], color: "#EDEDF2"))
        a.append(s("netlify", "Netlify", .hosting, status: "https://www.netlifystatus.com", probes: ["https://api.netlify.com"],
                   packages: ["netlify-cli", "@netlify/*"], env: ["NETLIFY_"], hosts: ["netlify.app"], color: "#32E6E2"))
        a.append(s("railway", "Railway", .hosting, status: "https://status.railway.com", probes: ["https://backboard.railway.com/graphql/v2"],
                   env: ["RAILWAY_"], hosts: ["railway.app", "up.railway.app", "rlwy.net", "proxy.rlwy.net"], color: "#B47CFF", feed: "none"))
        a.append(s("render", "Render", .hosting, status: "https://status.render.com", probes: ["https://api.render.com"],
                   env: ["RENDER_"], hosts: ["onrender.com"], color: "#9B7BFF"))
        a.append(s("fly", "Fly.io", .hosting, status: "https://status.flyio.net", probes: ["https://api.fly.io"],
                   env: ["FLY_"], hosts: ["fly.dev", "fly.io"], color: "#A58BFF"))
        a.append(s("heroku", "Heroku", .hosting, status: "https://status.heroku.com", probes: ["https://api.heroku.com"],
                   env: ["HEROKU_"], hosts: ["herokuapp.com"], color: "#9E7CC1", feed: "none"))
        a.append(s("cloudflare", "Cloudflare", .infra, status: "https://www.cloudflarestatus.com", probes: ["https://api.cloudflare.com"],
                   packages: ["wrangler", "@cloudflare/*", "cloudflare"], env: ["CLOUDFLARE_", "CF_API", "CF_ACCOUNT"],
                   hosts: ["workers.dev", "pages.dev", "r2.cloudflarestorage.com"], color: "#F6821F"))
        a.append(s("digitalocean", "DigitalOcean", .hosting, status: "https://status.digitalocean.com", probes: ["https://api.digitalocean.com"],
                   env: ["DIGITALOCEAN_", "DO_SPACES"], hosts: ["digitaloceanspaces.com", "ondigitalocean.app"], color: "#3D9BFF"))
        a.append(s("aws", "AWS", .infra, probes: ["https://sts.amazonaws.com"],
                   packages: ["aws-sdk", "@aws-sdk/*", "boto3", "aws-cdk-lib", "aws-amplify", "@aws-amplify/*"], env: ["AWS_"],
                   hosts: ["amazonaws.com"], color: "#FF9900"))
        a.append(s("gcp", "Google Cloud", .infra, probes: ["https://cloudresourcemanager.googleapis.com"],
                   packages: ["@google-cloud/*", "google-cloud-*"], env: ["GOOGLE_APPLICATION_CREDENTIALS", "GCP_", "GCLOUD_"],
                   color: "#5B9BFF"))
        a.append(s("expo", "Expo EAS", .devtools, status: "https://status.expo.dev", probes: ["https://exp.host"],
                   packages: ["expo", "eas-cli"], env: ["EXPO_TOKEN"], color: "#D8D8E8"))

        // MARK: Payments and fintech
        a.append(s("stripe", "Stripe", .payments, status: "https://status.stripe.com", probes: ["https://api.stripe.com/healthcheck"],
                   packages: ["stripe", "@stripe/*"], env: ["STRIPE_", "NEXT_PUBLIC_STRIPE"], hosts: ["api.stripe.com"],
                   auth: bearer("https://api.stripe.com/v1/balance", ["STRIPE_SECRET_KEY", "STRIPE_API_KEY", "STRIPE_KEY"]),
                   color: "#8C82FF", feed: "none"))
        a.append(s("paypal", "PayPal", .payments, probes: ["https://api-m.paypal.com"],
                   packages: ["@paypal/*", "paypal-rest-sdk"], env: ["PAYPAL_"], hosts: ["paypal.com"], color: "#2BA8E8"))
        a.append(s("plaid", "Plaid", .payments, status: "https://status.plaid.com", probes: ["https://production.plaid.com"],
                   packages: ["plaid", "react-plaid-link", "react-native-plaid-link-sdk"], env: ["PLAID_"], hosts: ["plaid.com"],
                   color: "#2FD8B0"))
        a.append(s("lemonsqueezy", "Lemon Squeezy", .payments, status: "https://status.lemonsqueezy.com", probes: ["https://api.lemonsqueezy.com"],
                   packages: ["@lemonsqueezy/*"], env: ["LEMONSQUEEZY_", "LEMON_SQUEEZY"], color: "#FFC233"))
        a.append(s("paddle", "Paddle", .payments, status: "https://paddlestatus.com", probes: ["https://api.paddle.com"],
                   packages: ["@paddle/*"], env: ["PADDLE_"], color: "#FDDD35"))
        a.append(s("bridge", "Bridge", .payments, probes: ["https://api.bridge.xyz"],
                   env: ["BRIDGE_"], hosts: ["bridge.xyz"], color: "#7C6CFF"))
        a.append(s("circle", "Circle", .payments, status: "https://status.circle.com", probes: ["https://api.circle.com"],
                   packages: ["@circle-fin/*"], env: ["CIRCLE_"], hosts: ["api.circle.com"], color: "#5DA0FF"))
        a.append(s("wise", "Wise", .payments, probes: ["https://api.wise.com"],
                   env: ["WISE_", "TRANSFERWISE_"], hosts: ["api.wise.com", "api.transferwise.com"], color: "#9FE870"))
        a.append(s("sumsub", "Sumsub", .auth, probes: ["https://api.sumsub.com"],
                   packages: ["@sumsub/*"], env: ["SUMSUB_"], hosts: ["sumsub.com"], color: "#3BA0FF"))
        a.append(s("persona", "Persona", .auth, status: "https://status.withpersona.com", probes: ["https://withpersona.com"],
                   env: ["PERSONA_"], hosts: ["withpersona.com"], color: "#9C8CFF"))

        // MARK: Auth
        a.append(s("privy", "Privy", .auth, status: "https://status.privy.io", probes: ["https://auth.privy.io"],
                   packages: ["@privy-io/*"], env: ["PRIVY_", "NEXT_PUBLIC_PRIVY", "EXPO_PUBLIC_PRIVY"], hosts: ["privy.io"],
                   color: "#9D8CFF"))
        a.append(s("clerk", "Clerk", .auth, status: "https://status.clerk.com", probes: ["https://api.clerk.com"],
                   packages: ["@clerk/*"], env: ["CLERK_", "NEXT_PUBLIC_CLERK", "EXPO_PUBLIC_CLERK"], hosts: ["clerk.com", "clerk.accounts.dev"],
                   color: "#8A6BFF"))
        a.append(s("auth0", "Auth0", .auth, status: "https://status.auth0.com", probes: ["https://auth0.com"],
                   packages: ["auth0", "@auth0/*", "react-native-auth0"], env: ["AUTH0_"], hosts: ["auth0.com"], color: "#FF6A3D"))
        a.append(s("workos", "WorkOS", .auth, status: "https://status.workos.com", probes: ["https://api.workos.com"],
                   packages: ["@workos-inc/*", "workos"], env: ["WORKOS_"], color: "#7B7BFF"))

        // MARK: Email and messaging
        a.append(s("resend", "Resend", .email, status: "https://resend-status.com", probes: ["https://api.resend.com"],
                   packages: ["resend", "@react-email/*"], env: ["RESEND_"], hosts: ["api.resend.com"], color: "#E5E5EA"))
        a.append(s("sendgrid", "SendGrid", .email, status: "https://status.sendgrid.com", probes: ["https://api.sendgrid.com"],
                   packages: ["@sendgrid/*", "sendgrid"], env: ["SENDGRID_"], hosts: ["api.sendgrid.com"], color: "#3AA0FF"))
        a.append(s("postmark", "Postmark", .email, status: "https://status.postmarkapp.com", probes: ["https://api.postmarkapp.com"],
                   packages: ["postmark"], env: ["POSTMARK_"], color: "#FFDE00"))
        a.append(s("mailgun", "Mailgun", .email, status: "https://status.mailgun.com", probes: ["https://api.mailgun.net"],
                   packages: ["mailgun.js", "mailgun-js"], env: ["MAILGUN_"], hosts: ["api.mailgun.net", "api.eu.mailgun.net"], color: "#F37A74"))
        a.append(s("twilio", "Twilio", .messaging, status: "https://status.twilio.com", probes: ["https://api.twilio.com"],
                   packages: ["twilio"], env: ["TWILIO_"], hosts: ["api.twilio.com"], color: "#FF4D63"))
        a.append(s("slack", "Slack", .messaging, status: "https://status.slack.com", probes: ["https://slack.com/api/api.test"],
                   packages: ["@slack/*", "slack-sdk", "slack_bolt"], env: ["SLACK_"], hosts: ["hooks.slack.com", "slack.com"],
                   color: "#ECB22E", feed: "none"))
        a.append(s("discord", "Discord", .messaging, status: "https://discordstatus.com", probes: ["https://discord.com/api/v10/gateway"],
                   packages: ["discord.js", "discord.py", "@discordjs/*"], env: ["DISCORD_"], hosts: ["discord.com"], color: "#7983F5"))
        a.append(s("telegram", "Telegram Bot API", .messaging, probes: ["https://api.telegram.org"],
                   packages: ["telegraf", "node-telegram-bot-api", "grammy", "python-telegram-bot", "aiogram"], env: ["TELEGRAM_"],
                   hosts: ["api.telegram.org"], color: "#2AABEE"))
        a.append(s("whatsapp", "WhatsApp Cloud API", .messaging, status: "https://metastatus.com", probes: ["https://graph.facebook.com"],
                   packages: ["whatsapp-web.js", "@whiskeysockets/baileys"], env: ["WHATSAPP_", "WA_PHONE", "META_WA"],
                   hosts: ["graph.facebook.com"], color: "#25D366"))
        a.append(s("pusher", "Pusher", .messaging, status: "https://status.pusher.com", probes: ["https://api.pusherapp.com"],
                   packages: ["pusher", "pusher-js"], env: ["PUSHER_", "NEXT_PUBLIC_PUSHER"], color: "#4F6BFF"))
        a.append(s("ably", "Ably", .messaging, status: "https://status.ably.com", probes: ["https://rest.ably.io/time"],
                   packages: ["ably"], env: ["ABLY_"], color: "#FF5416"))
        a.append(s("onesignal", "OneSignal", .messaging, status: "https://status.onesignal.com", probes: ["https://api.onesignal.com"],
                   packages: ["onesignal-node", "react-native-onesignal", "@onesignal/*", "OneSignal*"], env: ["ONESIGNAL_"], color: "#E54B4D"))
        a.append(s("knock", "Knock", .messaging, status: "https://status.knock.app", probes: ["https://api.knock.app"],
                   packages: ["@knocklabs/*"], env: ["KNOCK_"], color: "#FF6F4C"))

        // MARK: Dev tools
        a.append(s("github", "GitHub", .devtools, status: "https://www.githubstatus.com", probes: ["https://api.github.com"],
                   packages: ["@octokit/*", "octokit", "PyGithub"], env: ["GITHUB_TOKEN", "GH_TOKEN", "GITHUB_APP"], hosts: ["api.github.com"],
                   auth: bearer("https://api.github.com/rate_limit", ["GITHUB_TOKEN", "GH_TOKEN"]), color: "#E6EDF3"))
        a.append(s("gitlab", "GitLab", .devtools, status: "https://status.gitlab.com", probes: ["https://gitlab.com/api/v4/version"],
                   env: ["GITLAB_"], hosts: ["gitlab.com"], color: "#FC6D26"))
        a.append(s("bitbucket", "Bitbucket", .devtools, status: "https://bitbucket.status.atlassian.com", probes: ["https://api.bitbucket.org/2.0"],
                   env: ["BITBUCKET_"], hosts: ["bitbucket.org"], color: "#2684FF"))
        a.append(s("npm", "npm registry", .devtools, status: "https://status.npmjs.org", probes: ["https://registry.npmjs.org/-/ping"],
                   color: "#FF5A5F"))
        a.append(s("pypi", "PyPI", .devtools, status: "https://status.python.org", probes: ["https://pypi.org/simple/"],
                   color: "#4B8BBE"))
        a.append(s("dockerhub", "Docker Hub", .devtools, status: "https://www.dockerstatus.com", probes: ["https://registry-1.docker.io/v2/"],
                   color: "#2496ED"))
        a.append(s("sentry", "Sentry", .devtools, status: "https://status.sentry.io", probes: ["https://sentry.io/api/0/"],
                   packages: ["@sentry/*", "sentry-sdk", "Sentry", "sentry_flutter"], env: ["SENTRY_", "NEXT_PUBLIC_SENTRY"],
                   hosts: ["sentry.io", "ingest.sentry.io", "ingest.us.sentry.io", "ingest.de.sentry.io"], color: "#A68BFF"))
        a.append(s("datadog", "Datadog", .devtools, status: "https://status.datadoghq.com", probes: ["https://api.datadoghq.com/api/v1/validate"],
                   packages: ["dd-trace", "datadog", "@datadog/*", "ddtrace"], env: ["DD_API", "DATADOG_"], hosts: ["datadoghq.com"],
                   color: "#9B6BFF"))
        a.append(s("inngest", "Inngest", .devtools, status: "https://status.inngest.com", probes: ["https://api.inngest.com"],
                   packages: ["inngest"], env: ["INNGEST_"], color: "#D6E3FF"))
        a.append(s("trigger", "Trigger.dev", .devtools, status: "https://status.trigger.dev", probes: ["https://api.trigger.dev"],
                   packages: ["@trigger.dev/*"], env: ["TRIGGER_SECRET", "TRIGGER_API"], color: "#A8FF53"))
        a.append(s("linear", "Linear", .devtools, status: "https://linearstatus.com", probes: ["https://api.linear.app/graphql"],
                   packages: ["@linear/sdk"], env: ["LINEAR_"], color: "#8C8FFF"))

        // MARK: Analytics
        a.append(s("posthog", "PostHog", .analytics, status: "https://status.posthog.com", probes: ["https://us.i.posthog.com/_health"],
                   packages: ["posthog-js", "posthog-node", "posthog-react-native", "posthog"], env: ["POSTHOG_", "NEXT_PUBLIC_POSTHOG", "EXPO_PUBLIC_POSTHOG"],
                   hosts: ["posthog.com", "i.posthog.com"], color: "#F9BD2B"))
        a.append(s("mixpanel", "Mixpanel", .analytics, status: "https://status.mixpanel.com", probes: ["https://api.mixpanel.com"],
                   packages: ["mixpanel", "mixpanel-browser", "mixpanel-react-native"], env: ["MIXPANEL_", "NEXT_PUBLIC_MIXPANEL"], color: "#8D6BFF"))
        a.append(s("segment", "Segment", .analytics, status: "https://status.segment.com", probes: ["https://api.segment.io"],
                   packages: ["@segment/*", "analytics-node"], env: ["SEGMENT_"], color: "#52BD94"))
        a.append(s("amplitude", "Amplitude", .analytics, status: "https://status.amplitude.com", probes: ["https://api2.amplitude.com"],
                   packages: ["@amplitude/*"], env: ["AMPLITUDE_"], color: "#4E8DFF"))

        // MARK: Search, storage, content
        a.append(s("algolia", "Algolia", .search, status: "https://status.algolia.com", probes: ["https://status.algolia.com"],
                   packages: ["algoliasearch", "react-instantsearch*", "instantsearch.js"], env: ["ALGOLIA_", "NEXT_PUBLIC_ALGOLIA"],
                   hosts: ["algolia.net", "algolianet.com"], color: "#5468FF"))
        a.append(s("cloudinary", "Cloudinary", .storage, status: "https://status.cloudinary.com", probes: ["https://api.cloudinary.com"],
                   packages: ["cloudinary", "next-cloudinary"], env: ["CLOUDINARY_"], hosts: ["res.cloudinary.com"], color: "#5A6FFF"))
        a.append(s("uploadthing", "UploadThing", .storage, status: "https://status.uploadthing.com", probes: ["https://api.uploadthing.com"],
                   packages: ["uploadthing", "@uploadthing/*"], env: ["UPLOADTHING_"], color: "#FF4D4D"))
        a.append(s("sanity", "Sanity", .storage, status: "https://www.sanity-status.com", probes: ["https://api.sanity.io"],
                   packages: ["@sanity/*", "sanity", "next-sanity"], env: ["SANITY_", "NEXT_PUBLIC_SANITY"], hosts: ["sanity.io"], color: "#F36458"))
        a.append(s("contentful", "Contentful", .storage, status: "https://www.contentfulstatus.com", probes: ["https://cdn.contentful.com"],
                   packages: ["contentful", "contentful-management"], env: ["CONTENTFUL_"], color: "#4FB5E1"))
        a.append(s("shopify", "Shopify", .payments, status: "https://www.shopifystatus.com", probes: ["https://shopify.dev"],
                   packages: ["@shopify/*", "shopify-api-node"], env: ["SHOPIFY_"], hosts: ["myshopify.com"], color: "#95BF47"))
        a.append(s("notion", "Notion API", .devtools, status: "https://www.notion-status.com", probes: ["https://api.notion.com"],
                   packages: ["@notionhq/client", "notion-client"], env: ["NOTION_"], hosts: ["api.notion.com"],
                   auth: bearer("https://api.notion.com/v1/users/me", ["NOTION_API_KEY", "NOTION_TOKEN", "NOTION_KEY"], extra: ["Notion-Version": "2022-06-28"]),
                   color: "#E5E5EA"))
        a.append(s("mapbox", "Mapbox", .other, status: "https://status.mapbox.com", probes: ["https://api.mapbox.com"],
                   packages: ["mapbox-gl", "@rnmapbox/*", "@mapbox/*", "react-map-gl"], env: ["MAPBOX_", "NEXT_PUBLIC_MAPBOX"], color: "#4C7BFF"))
        a.append(s("googlemaps", "Google Maps", .other, probes: ["https://maps.googleapis.com"],
                   packages: ["@react-google-maps/*", "@googlemaps/*", "@vis.gl/react-google-maps"], env: ["GOOGLE_MAPS", "NEXT_PUBLIC_GOOGLE_MAPS"],
                   hosts: ["maps.googleapis.com"], color: "#34C759"))

        // MARK: Web3
        a.append(s("alchemy", "Alchemy", .web3, status: "https://status.alchemy.com", probes: ["https://dashboard.alchemy.com"],
                   packages: ["alchemy-sdk", "@alch/*", "@account-kit/*"], env: ["ALCHEMY_", "NEXT_PUBLIC_ALCHEMY"],
                   hosts: ["alchemy.com", "alchemyapi.io"], color: "#5A7CFF"))
        a.append(s("infura", "Infura", .web3, status: "https://status.infura.io", probes: ["https://infura.io"],
                   env: ["INFURA_"], hosts: ["infura.io"], color: "#FF6B4A"))
        a.append(s("quicknode", "QuickNode", .web3, status: "https://status.quicknode.com", probes: ["https://www.quicknode.com"],
                   env: ["QUICKNODE_", "QN_"], hosts: ["quiknode.pro"], color: "#5FF3C1"))
        a.append(s("base", "Base", .web3, status: "https://status.base.org", probes: ["https://mainnet.base.org"],
                   packages: ["@coinbase/onchainkit", "@base-org/*"], env: ["BASE_RPC", "NEXT_PUBLIC_BASE"], hosts: ["base.org"],
                   color: "#3D7BFF"))
        a.append(s("coinbase", "Coinbase CDP", .web3, status: "https://status.coinbase.com", probes: ["https://api.cdp.coinbase.com"],
                   packages: ["@coinbase/*", "cdp-sdk"], env: ["COINBASE_", "CDP_API"], hosts: ["api.coinbase.com", "api.cdp.coinbase.com"],
                   color: "#3D7BFF"))
        a.append(s("walletconnect", "WalletConnect", .web3, probes: ["https://relay.walletconnect.com"],
                   packages: ["@walletconnect/*", "@reown/*", "@web3modal/*"], env: ["WALLETCONNECT_", "NEXT_PUBLIC_WALLETCONNECT", "NEXT_PUBLIC_WC_", "REOWN_"],
                   color: "#3B99FC"))
        return a
    }()
}
