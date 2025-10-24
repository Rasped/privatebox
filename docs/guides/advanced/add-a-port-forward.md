# How-To: Add a Port Forward

A port forward allows a specific application or service running on your local network (like a game server, web server, or remote access program) to be accessible from the internet. This guide explains how to create one.

*Note: You must be connected to your **Trusted** network to access the OPNsense interface.*

---

### 1. Access OPNsense

Open a web browser and go to:

`https://opnsense.lan`

Log in with the following credentials:
- **Username:** `root`
- **Password:** Your `adminpassword`, which is printed on the sticker on the bottom of your PrivateBox.

### 2. Navigate to Port Forward Rules

In the left-hand navigation menu, go to:

`Firewall` -> `NAT` -> `Port Forward`

### 3. Add a New Rule

Click the **`+ Add`** button in the upper-right corner of the screen to open the rule creation page.

Fill out the form with the following information:

- **Interface:** Leave this as `WAN`.
- **Protocol:** Choose the protocol required by your application. `TCP/UDP` is a safe default if you are unsure.
- **Destination / WAN address:** Leave this as `any`.
- **Destination port range:** Enter the port you want to open to the internet. For a single port, enter the same number in both the "from" and "to" fields (e.g., `8080`).
- **Redirect target IP:** Enter the IP address of the device on your local network that is running the service (e.g., `10.10.10.150`).
- **Redirect target port:** Enter the port the service is listening on. This is often the same as the destination port.
- **Description:** Give your rule a memorable name, such as `Minecraft Server` or `Plex Remote Access`.

### 4. Save and Apply

1.  Click the **`Save`** button at the bottom of the page.
2.  A yellow bar will appear at the top of the screen. Click the **`Apply Changes`** button to activate your new rule.

Your port forward is now active.
