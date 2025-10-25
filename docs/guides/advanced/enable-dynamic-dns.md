# Advanced: How to enable dynamic DNS

Dynamic DNS (DDNS) gives your PrivateBox a stable domain name (e.g., `my-home.dedyn.io`) that stays updated even if your home IP address changes. This also allows the system to acquire a valid SSL certificate for that domain, removing the browser security warnings.

---

### Prerequisite: A DDNS provider account

Before you begin, you must have an account with one of the following supported DDNS providers and have generated an API Key or Token.

- **desec.io (Recommended)**
- **dynu.com**
- **duckdns.org**
- **Cloudflare**

*We recommend desec.io because, as a non-profit, their mission is closely aligned with the privacy-first ethos of Sub Rosa. For users who wish to minimize any contact with large cloud platforms, they are an excellent choice. Other services may be hosted on infrastructure like AWS.*

For desec.io, dynu.com, and duckdns.org, you can register a subdomain directly through their service. If you bring your own custom domain, the provider must host its DNS zone.

---

### 1. access semaphore

Semaphore is the automation engine used by your PrivateBox. You must be connected to your **Trusted** network to access it.

Open a web browser and go to:

`https://semaphore.lan`

Log in with the following credentials:
- **Username:** `admin`
- **Password:** Your `services password`, which is printed on the sticker on the bottom of your PrivateBox.

### 2. run the dyndns playbook

1.  In the left-hand navigation menu, click on **`Task Templates`**.
2.  Find the template named **`DynDNS Orchestration`** and click the blue **`>`** (Run) button next to it. This job runs the full DynDNS sequence (steps 1 through 7), so you don't need to launch each template manually.

### 3. Configure the parameters

You'll be taken to a "New Task" page where you'll provide the details for your DDNS provider.

- **`dns_provider`**: Select your provider from the dropdown menu.
- **`api_key`**: Paste the API Key or Token you generated from your provider's website.
- **`full_domain`**: Enter the full domain or subdomain you want to use (e.g., `my-privatebox.duckdns.org`).
- **`lets_encrypt_email`**: Enter your email address. Let's Encrypt will use this to send you notifications if your SSL certificate is expiring and renewal fails.
- **`cloudflare_zone_id`**: This field is **only** required if you are using Cloudflare. Paste your Cloudflare Zone ID here.

### 4. Run the task

Click the blue **`Run`** button at the bottom of the page.

Semaphore will execute the automation in the background. You can watch the progress on the task page. Once it completes successfully, your new domain is live.

---

### Accessing your services

After the playbook is finished, you can access your PrivateBox services using your new domain. For example, `https://opnsense.my-home.dedyn.io` will work with a valid SSL certificate (no browser warnings).

**Note:** Services are accessible from your local network or VPN. They're not exposed to the public internet.

---

### Verify the results

1. Open the task details in Semaphore and confirm every stage shows `ok` or `changed`. Any `failed` entry means the automation stopped early.
2. Visit your new domain in a browser. You should see a valid certificate issued by Let's Encrypt without security warnings.
3. If DNS hasn't updated yet, wait a few minutes and reload. Some providers cache records for up to 5 minutes.

---

### Troubleshooting

- **Authentication failed:** Double-check the API key or token in Semaphore. Regenerate it on the provider dashboard if you're unsure.
- **Domain not found:** Confirm the `full_domain` exists with your provider. For Cloudflare, the zone must already be added to your account.
- **Certificate request failed:** Ensure the domain resolves to your public IP. If you recently changed DNS records, wait a few minutes and rerun the orchestration.
- **Cloudflare specific:** Provide the Zone ID and use a token scoped to DNS edit permissions. Unscoped API keys can fail silently.
