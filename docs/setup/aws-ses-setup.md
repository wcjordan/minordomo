# AWS SES Setup Guide

This guide walks through the one-time AWS and Jenkins configuration required for the pipeline failure email notifications.

---

## Overview

The `shared/notify-failure.py` script sends emails via Amazon SES when a pipeline build fails. It requires:

1. An AWS IAM user or role with `ses:SendEmail` permission
2. A verified sender email address in SES
3. Two Jenkins credentials containing the AWS access key

---

## Step 1: Verify the Sender Email Address in SES

The sender address defaults to `NOTIFICATION_EMAIL`, which is set to `$JENKINS_USERNAME` (your Gmail address, e.g. `yourname@gmail.com`). Since sender and recipient are the same address, one verification covers both.

1. Open the [AWS SES console](https://console.aws.amazon.com/ses/).
2. In the left menu, choose **Verified identities** → **Create identity**.
3. Select **Email address**, enter your address, and click **Create identity**.
4. Check your inbox for the verification email from AWS and click the confirmation link.

### SES Sandbox Note

New AWS accounts are in SES sandbox mode, which restricts sending to verified addresses only. Because sender and recipient are the same verified address, sandbox mode works for this use case.

To send to arbitrary recipients in the future, request production access via **Account dashboard** → **Request production access** in the SES console.

---

## Step 2: Create an IAM User with SES Send Permission

1. Open the [AWS IAM console](https://console.aws.amazon.com/iam/).
2. Create a new IAM user (or reuse an existing one) with **programmatic access**.
3. Attach the following inline policy (or use `AmazonSESFullAccess` for simplicity, though the minimal policy below is preferred):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ses:SendEmail",
      "Resource": "arn:aws:ses:us-east-1:<ACCOUNT_ID>:identity/<YOUR_EMAIL>"
    }
  ]
}
```

Replace `<ACCOUNT_ID>` with your 12-digit AWS account ID and `<YOUR_EMAIL>` with the verified sender address.

4. Generate an **Access key ID** and **Secret access key** for the user. Save these values — you will need them in Step 3.

---

## Step 3: Add Jenkins Credentials

In your Jenkins instance, create two **Secret text** credentials:

| Credential ID               | Value                         |
|-----------------------------|-------------------------------|
| `aws-ses-access-key-id`     | The IAM user's Access Key ID  |
| `aws-ses-secret-access-key` | The IAM user's Secret Access Key |

**How to add:**
1. Go to **Jenkins** → **Manage Jenkins** → **Credentials** → **(global)** → **Add Credentials**.
2. Set **Kind** to `Secret text`.
3. Enter the credential ID exactly as shown above.
4. Paste the key value and save.

Repeat for the second credential.

---

## Step 4: Recommended Region

The default SES region is `us-east-1`. If you prefer a different region, set the `AWS_SES_REGION` environment variable in the pipeline or in `shared/setup-env.sh`. Make sure the email identity is verified in the same region.

---

## Environment Variables Reference

| Variable               | Required | Default              | Description                          |
|------------------------|----------|----------------------|--------------------------------------|
| `NOTIFICATION_EMAIL`   | Yes      | (set by setup-env.sh)| Recipient address                    |
| `AWS_ACCESS_KEY_ID`    | Yes      | —                    | AWS access key (from Jenkins cred)   |
| `AWS_SECRET_ACCESS_KEY`| Yes      | —                    | AWS secret key (from Jenkins cred)   |
| `AWS_SES_REGION`       | No       | `us-east-1`          | SES region                           |
| `SES_SENDER_EMAIL`     | No       | `NOTIFICATION_EMAIL` | Sender address (must be verified)    |
