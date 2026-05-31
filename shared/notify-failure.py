#!/usr/bin/env python3
"""Send a failure notification email via Amazon SES.

Usage: notify-failure.py --subject SUBJECT [--body-file FILE]

Environment variables:
  NOTIFICATION_EMAIL      Recipient address (required; if unset, exits 0 with warning)
  AWS_ACCESS_KEY_ID       SES credentials
  AWS_SECRET_ACCESS_KEY   SES credentials
  AWS_SES_REGION          SES region (default: us-east-1)
  SES_SENDER_EMAIL        Sender address (default: NOTIFICATION_EMAIL)
"""

import argparse
import os
import sys


def parse_args():
    parser = argparse.ArgumentParser(description="Send SES failure notification email")
    parser.add_argument("--subject", required=True, help="Email subject line")
    parser.add_argument("--body-file", help="Path to file containing email body text")
    return parser.parse_args()


def main():
    args = parse_args()

    recipient = os.environ.get("NOTIFICATION_EMAIL", "").strip()
    if not recipient:
        print("WARNING: NOTIFICATION_EMAIL is not set; skipping notification", file=sys.stderr)
        sys.exit(0)

    body = ""
    if args.body_file:
        try:
            with open(args.body_file) as f:
                body = f.read()
        except OSError as e:
            print(f"WARNING: Could not read body file {args.body_file}: {e}", file=sys.stderr)

    region = os.environ.get("AWS_SES_REGION", "us-east-1")
    sender = os.environ.get("SES_SENDER_EMAIL", recipient)

    try:
        import boto3  # lazy import so --help and missing-env path work without boto3 installed

        client = boto3.client(
            "ses",
            region_name=region,
            aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
            aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
        )
        client.send_email(
            Source=sender,
            Destination={"ToAddresses": [recipient]},
            Message={
                "Subject": {"Data": args.subject, "Charset": "UTF-8"},
                "Body": {"Text": {"Data": body, "Charset": "UTF-8"}},
            },
        )
        print(f"Notification sent to {recipient}")
    except Exception as e:
        print(f"WARNING: Failed to send SES notification: {e}", file=sys.stderr)

    sys.exit(0)


if __name__ == "__main__":
    main()
