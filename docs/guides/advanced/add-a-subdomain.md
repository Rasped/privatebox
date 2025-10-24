# How-to: Add a subdomain for a new application

This guide explains how to make your newly installed application accessible via a clean, secure subdomain (e.g., `https://myapp.privatebox.lan`).

## Prerequisite

You must have already deployed your application as a container and connected it to the `services_network`. If you have not done this, please follow the [How to Add New Applications](./add-apps.md) guide first.

---

## 1. Understanding the reverse proxy

Your PrivateBox uses a service called **Caddy** as a reverse proxy. Its job is to direct traffic from a clean URL to the correct internal container and port. This is all configured in a single, simple text file called the `Caddyfile`.

To add a new subdomain, you just need to add a new entry to this file.

## 2. Editing the Caddyfile

### Step 1: Connect to your PrivateBox

You will need to use SSH to log into the management VM to edit the file.

*(Instructions on how to SSH into the management VM will be added here. This may require its own short, separate guide.)*

### Step 2: Edit the file

1.  Once you are logged in via SSH, open the Caddyfile for editing using a text editor like `nano`:
    ```bash
    nano /var/data/caddy/Caddyfile
    ```
2.  Scroll to the bottom of the file.
3.  Add a new block for your application. The format is `subdomain.privatebox.lan { reverse_proxy container_name:port }`.

**Example:** If you installed Uptime Kuma in a container named `kuma` that uses port `3001`, you would add:

```
kuma.privatebox.lan {
    reverse_proxy kuma:3001
}
```

4.  Save the file and exit `nano` (press `Ctrl+X`, then `Y`, then `Enter`).

## 3. Reloading Caddy

For Caddy to recognize the new subdomain, you must reload its configuration. The easiest way to do this is by restarting the Caddy container.

1.  Navigate to your Portainer dashboard at `https://portainer.lan`.
2.  In the left-hand menu, click on **Containers**.
3.  Find the container named `caddy` in the list.
4.  Click the **Restart** icon (a circular arrow) in the **Actions** column for the `caddy` container.

## 4. Done!

That's it. Caddy will restart with the new configuration. You can now access your new application at the subdomain you configured (e.g., `https://kuma.privatebox.lan`). It will be automatically secured with HTTPS, just like all the other system services.
