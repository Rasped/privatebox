# Advanced: How to Enable Dynamic DNS

Dynamic DNS (DDNS) gives your PrivateBox a stable, memorable domain name (e.g., `my-home.duckdns.org`) that stays updated even if your home IP address changes. This also allows the system to acquire a valid SSL certificate for that domain, removing the browser security warnings.

---

### Prerequisite: A DDNS Provider Account

Before you begin, you must have an account with one of the following supported DDNS providers and have generated an API Key or Token.

- **desec.io (Recommended)**
- **dynu.com**
- **duckdns.org**
- **Cloudflare**

*We recommend desec.io because, as a non-profit, their mission is closely aligned with the privacy-first ethos of Sub Rosa. For users who wish to minimize any contact with large cloud platforms, they are an excellent choice. Other services may be hosted on infrastructure like AWS.*

This process will also require you to have a registered domain name with that provider.

---

### 1. Access Semaphore

Semaphore is the automation engine used by your PrivateBox. You must be connected to your **Trusted** network to access it.

Open a web browser and go to:

`https://semaphore.lan`

Log in with the following credentials:
- **Username:** `admin`
- **Password:** Your `services password`, which is printed on the sticker on the bottom of your PrivateBox.

### 2. Run the DynDNS Playbook

1.  In the left-hand navigation menu, click on **`Task Templates`**.
2.  Find the template named **`DynDNS 1: Setup Environment`** and click the blue **`>`** (Run) button next to it.

### 3. Configure the Parameters

You will be taken to a "New Task" page where you must provide the details for your DDNS provider.

- **`dns_provider`**: Select your provider from the dropdown menu.
- **`api_key`**: Paste the API Key or Token you generated from your provider's website.
- **`full_domain`**: Enter the full domain or subdomain you want to use (e.g., `my-privatebox.duckdns.org`).
- **`lets_encrypt_email`**: Enter your email address. Let's Encrypt will use this to send you notifications if your SSL certificate is expiring and renewal fails.
- **`cloudflare_zone_id`**: This field is **only** required if you are using Cloudflare. Paste your Cloudflare Zone ID here.

### 4. Run the Task

Click the blue **`Run`** button at the bottom of the page.

Semaphore will now execute the automation in the background. You can watch the progress on the task page. Once it completes successfully, your new domain is live.

---

### Accessing Your Services

After the playbook is finished, you can access your PrivateBox services securely via your new domain. For example, `https://opnsense.my-home.duckdns.org` will now work and will have a valid SSL certificate.
