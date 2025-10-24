# Advanced: Using the health check system

This guide explains how to use the PrivateBox's built-in health check system to diagnose and troubleshoot issues.

## 1. Introduction

The health check system is a built-in diagnostic tool designed to verify that all parts of your PrivateBox are working correctly. It runs over 90 different checks across your entire system.

There are two main reasons you would use it:

1.  **Self-diagnosis:** If you're experiencing a problem (e.g., slow internet, a service isn't accessible), the health check is the first step to finding the root cause yourself.
2.  **Support:** If you can't solve the problem, the system can generate a detailed, anonymous report that helps our support team diagnose the issue much faster.

## 2. Running a health check

1.  Access your Semaphore dashboard at `https://semaphore.lan`.
2.  Navigate to **Task Templates** in the left-hand menu.
3.  Find the template named **`Diagnostics: Run Full System Health Check`**.
4.  Click the blue **Run (`>`)** button.

This process will take a few minutes to complete as it thoroughly tests every component of your system.

## 3. Understanding the results

Once the check is complete, the results will be displayed in a new "System Health" dashboard on your main PrivateBox homepage (`http://privatebox.lan`).

### The overall status

At the top of the page, you will see a clear, overall status:

*   ✅ **Healthy:** All systems are operating correctly.
*   ⚠️ **Warning:** The system is functional, but one or more components are approaching a limit (e.g., high CPU usage) or have a minor issue.
*   ❌ **Critical:** A core component has failed. The system is likely experiencing a significant issue.

### Reading a diagnostic chain

For complex services like DNS, instead of just telling you it's "broken," the diagnostic chain shows you exactly *where* it broke.

**Example DNS Failure:**

- ✅ AdGuard Home service running
- ✅ AdGuard listening on port 53
- ✅ AdGuard → Quad9 connection established
- ❌ **Quad9 DNS query timeout (exceeded 5s)**
- ⚠️ Fallback to Unbound: Successful

This result tells you instantly that your local system is working perfectly, but the external DNS provider (Quad9) is having issues.

## 4. Generating a support report

You should only need to use this feature if the health check shows a critical error that you cannot resolve with the [Troubleshooting Guide](../troubleshooting-guide.md).

1.  In Semaphore, run the **`Diagnostics: Generate Support Report`** task.
2.  When the task completes, it will display a unique **Report ID** (e.g., `SR-2025-1018-B7C1`).
3.  When you contact support, provide this Report ID. There is no need to send any files.

The support report contains only technical, non-personal information such as system logs and configuration settings. It is automatically sanitized to remove all passwords, IP addresses, and other potentially sensitive data before it is generated.
