import boto3
import json
import logging
import os
import urllib.request

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def send_slack_alert(instance_id, target_type, region, success, reason=""):
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook_url:
        logger.warning("SLACK_WEBHOOK_URL not set — skipping Slack notification.")
        return

    if success:
        message = {
            "text": (
                f":white_check_mark: *EC2 Resize Successful!*\n"
                f"*Instance* : `{instance_id}`\n"
                f"*New type* : `{target_type}`\n"
                f"*Region*   : `{region}`"
            )
        }
    else:
        message = {
            "text": (
                f":rotating_light: *EC2 Resize Failed!*\n"
                f"*Instance* : `{instance_id}`\n"
                f"*Target type* : `{target_type}`\n"
                f"*Region*   : `{region}`\n"
                f"*Reason*   : {reason}"
            )
        }

    data = json.dumps(message).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"}
    )
    try:
        urllib.request.urlopen(req)
        logger.info("Slack notification sent.")
    except Exception as e:
        logger.error(f"Failed to send Slack notification: {e}")


def lambda_handler(event, context):
    logger.info(f"Event received: {json.dumps(event)}")

    instance_id = event.get("instance_id")
    target_type = event.get("target_type")
    region      = event.get("region", "ap-south-1")

    # ── Validate ──────────────────────────────────────────────────────────────
    if not instance_id or not target_type:
        reason = "Missing required fields: 'instance_id' or 'target_type'."
        logger.error(reason)
        send_slack_alert(instance_id, target_type, region, success=False, reason=reason)
        return {"statusCode": 400, "body": reason}

    # ── Fetch instance details ─────────────────────────────────────────────────
    ec2 = boto3.client("ec2", region_name=region)

    try:
        response  = ec2.describe_instances(InstanceIds=[instance_id])
        instance  = response["Reservations"][0]["Instances"][0]
        state     = instance["State"]["Name"]
        curr_type = instance["InstanceType"]
    except Exception as e:
        reason = f"Could not find instance {instance_id}. Error: {str(e)}"
        logger.error(reason)
        send_slack_alert(instance_id, target_type, region, success=False, reason=reason)
        return {"statusCode": 400, "body": reason}

    logger.info(f"Instance state: {state} | Current type: {curr_type} | Target type: {target_type}")

    # ── Already the target type — nothing to do ────────────────────────────────
    if curr_type == target_type:
        msg = f"Instance {instance_id} is already {target_type}. No change needed."
        logger.info(msg)
        return {"statusCode": 200, "body": msg}

    # ── Must be stopped before resizing ───────────────────────────────────────
    if state != "stopped":
        reason = (
            f"Instance `{instance_id}` is in *{state}* state. "
            f"It must be fully STOPPED before resizing."
        )
        logger.error(reason)
        send_slack_alert(instance_id, target_type, region, success=False, reason=reason)
        return {"statusCode": 400, "body": reason}

    # ── Resize ────────────────────────────────────────────────────────────────
    try:
        ec2.modify_instance_attribute(
            InstanceId=instance_id,
            InstanceType={"Value": target_type}
        )
    except Exception as e:
        reason = f"Resize failed for {instance_id}. Error: {str(e)}"
        logger.error(reason)
        send_slack_alert(instance_id, target_type, region, success=False, reason=reason)
        return {"statusCode": 500, "body": reason}

    msg = f"Success! Instance {instance_id} resized from {curr_type} to {target_type}."
    logger.info(msg)
    send_slack_alert(instance_id, target_type, region, success=True)
    return {"statusCode": 200, "body": msg}