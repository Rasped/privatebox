# How-to: Add new applications

This guide explains how to install your own self-hosted applications on your PrivateBox.

## 1. The philosophy

PrivateBox provides a secure and stable foundation for your network. While we provide a core set of services, we believe you should have the freedom to build on top of that foundation. The easiest way to add new applications is by using containers, which you can manage through the Portainer web interface.

---

## 2. Accessing Portainer

- **Prerequisite:** You must have already created your Portainer admin account. If you have not, please follow the [setup-portainer.md](./setup-portainer.md) guide first.
- **Step 1:** Navigate to `https://portainer.lan` in your web browser.
- **Step 2:** Log in with the credentials you created.

## 3. Adding an application via a stack

The best way to manage applications in Portainer is by using a "Stack," which is a simple text file that defines the application and its configuration (also known as a `docker-compose` file).

In this example, we will add **Uptime Kuma**, a popular and easy-to-use monitoring tool.

### Step 1: Create a new stack

1.  In Portainer, make sure you are managing the **local** environment.
2.  In the left-hand menu, click on **Stacks**.
3.  Click the **+ Add stack** button.

### Step 2: Configure the stack

1.  **Name:** Give your stack a simple name, like `kuma`.
2.  **Web editor:** Paste the following text into the web editor. This is a standard `docker-compose.yml` for Uptime Kuma, with one important modification.

```yaml
version: '3.3'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    volumes:
      - /var/data/uptime-kuma:/app/data
    ports:
      - 3001:3001
    restart: unless-stopped
    networks:
      - services_network

networks:
  services_network:
    external: true
```

**Note:** The `networks` section at the bottom is essential. It tells your new application to connect to the PrivateBox's internal `services_network`, which allows it to be managed and accessed securely.

### Step 3: Deploy the stack

Scroll to the bottom of the page and click the **Deploy the stack** button. Portainer will now download the Uptime Kuma image and start the container.

---

## 4. Accessing your new application

Your Uptime Kuma container is now running. However, to access it with a clean, secure URL like `https://kuma.privatebox.lan`, you need to tell the Caddy reverse proxy about it.

To learn how to do this, please follow our guide: **(A new guide, `how-to-add-a-subdomain.md`, will be created and linked here).**
