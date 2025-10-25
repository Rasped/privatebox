# How-to: Update your system

**Status: Draft - Not yet implemented**

This feature is planned but not yet available in the current version of PrivateBox.

---

This guide explains how to update your PrivateBox to the latest version.

## The update philosophy

Unlike many consumer devices, your PrivateBox does not update itself automatically. This is a deliberate design choice to give you full control over your system. You choose when to update, ensuring that changes are never made without your knowledge and happen at a time that is convenient for you.

The update process works by re-running the automation playbooks with the latest version from the official PrivateBox GitHub repository.

---

### 1. Access the automation engine

All system tasks, including updates, are managed through the Semaphore automation engine.

- **Prerequisite:** You must be connected to your **Trusted** network.
- **Step 1:** Open a web browser and navigate to `https://semaphore.lan`.
- **Step 2:** Log in with the username `admin` and your unique `services password`.

### 2. Run the update task

- **Step 1:** In the left-hand navigation menu, click on **Task Templates**.
- **Step 2:** Find the template named **`System: Update All`**.
- **Step 3:** Click the blue **Run (`>`)** button to the right of the template name.

![Screenshot of the Semaphore Task Templates page, highlighting the "System: Update All" task.]

### 3. Monitor the update

After clicking run, you will be taken to a live task output page where you can see the automation in progress. The page will show the output of the Ansible playbook as it checks for new versions and applies any changes.

A successful update will end with a green "Playbook finished successfully" message.

### 4. Verification

After the update is complete, you can verify the new version by checking the version number of a core service, such as OPNsense, in its respective web interface.
