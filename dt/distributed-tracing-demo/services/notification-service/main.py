"""Notification Service - Handles order and system notifications."""

import os
import asyncio
import uuid
import random
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import structlog
from typing import Optional
import json

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("notification-service")

app = FastAPI(title="Notification Service", version="1.0.0")

class NotificationRequest(BaseModel):
    order_id: str
    user_id: str
    type: str = "order_confirmation"
    message: Optional[str] = None

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "notification-service"}

@app.post("/notifications/order-confirmation")
@trace_request("send_order_confirmation")
async def send_order_confirmation(
    notification_request: NotificationRequest,
    x_correlation_id: Optional[str] = Header(None)
):
    """Send order confirmation notification."""
    
    notification_id = f"notif-{uuid.uuid4()}"
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Order confirmation notification started",
                notification_id=notification_id,
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate multiple notification channels
        channels_sent = []
        
        # Send email notification
        if await send_email_notification(notification_request, correlation_id):
            channels_sent.append("email")
        
        # Send SMS notification
        if await send_sms_notification(notification_request, correlation_id):
            channels_sent.append("sms")
        
        # Send push notification
        if await send_push_notification(notification_request, correlation_id):
            channels_sent.append("push")
        
        logger.info("Order confirmation notification completed",
                   notification_id=notification_id,
                   order_id=notification_request.order_id,
                   channels_sent=channels_sent,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "success": True,
            "notification_id": notification_id,
            "order_id": notification_request.order_id,
            "channels_sent": channels_sent,
            "message": "Order confirmation notifications sent successfully"
        }
        
    except Exception as e:
        logger.error("Order confirmation notification failed",
                    notification_id=notification_id,
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Notification failed: {str(e)}")

@trace_request("send_email_notification")
async def send_email_notification(notification_request: NotificationRequest, correlation_id: str):
    """Send email notification."""
    
    logger.info("Sending email notification",
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate email service delay
        await asyncio.sleep(random.uniform(0.2, 0.5))
        
        # Simulate email template rendering
        await render_email_template(notification_request, correlation_id)
        
        # Simulate email delivery
        await deliver_email(notification_request, correlation_id)
        
        logger.info("Email notification sent successfully",
                   order_id=notification_request.order_id,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return True
        
    except Exception as e:
        logger.error("Email notification failed",
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return False

@trace_request("render_email_template")
async def render_email_template(notification_request: NotificationRequest, correlation_id: str):
    """Render email template for the notification."""
    await asyncio.sleep(random.uniform(0.05, 0.1))
    
    logger.debug("Email template rendered",
                order_id=notification_request.order_id,
                template="order_confirmation_template",
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("deliver_email")
async def deliver_email(notification_request: NotificationRequest, correlation_id: str):
    """Deliver email via email service provider."""
    await asyncio.sleep(random.uniform(0.1, 0.3))
    
    # Simulate occasional email delivery failures
    if random.random() < 0.05:
        raise Exception("Email delivery service temporarily unavailable")
    
    logger.debug("Email delivered successfully",
                order_id=notification_request.order_id,
                provider="sendgrid-simulation",
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("send_sms_notification")
async def send_sms_notification(notification_request: NotificationRequest, correlation_id: str):
    """Send SMS notification."""
    
    logger.info("Sending SMS notification",
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate SMS service delay
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        # Simulate SMS delivery
        await deliver_sms(notification_request, correlation_id)
        
        logger.info("SMS notification sent successfully",
                   order_id=notification_request.order_id,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return True
        
    except Exception as e:
        logger.error("SMS notification failed",
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return False

@trace_request("deliver_sms")
async def deliver_sms(notification_request: NotificationRequest, correlation_id: str):
    """Deliver SMS via SMS service provider."""
    await asyncio.sleep(random.uniform(0.05, 0.2))
    
    # Simulate occasional SMS delivery failures
    if random.random() < 0.03:
        raise Exception("SMS delivery service rate limited")
    
    logger.debug("SMS delivered successfully",
                order_id=notification_request.order_id,
                provider="twilio-simulation",
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("send_push_notification")
async def send_push_notification(notification_request: NotificationRequest, correlation_id: str):
    """Send push notification."""
    
    logger.info("Sending push notification",
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate push notification service delay
        await asyncio.sleep(random.uniform(0.05, 0.15))
        
        # Simulate push notification delivery
        await deliver_push_notification(notification_request, correlation_id)
        
        logger.info("Push notification sent successfully",
                   order_id=notification_request.order_id,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return True
        
    except Exception as e:
        logger.error("Push notification failed",
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return False

@trace_request("deliver_push_notification")
async def deliver_push_notification(notification_request: NotificationRequest, correlation_id: str):
    """Deliver push notification via push service provider."""
    await asyncio.sleep(random.uniform(0.02, 0.08))
    
    logger.debug("Push notification delivered successfully",
                order_id=notification_request.order_id,
                provider="fcm-simulation",
                correlation_id=correlation_id,
                **get_trace_context())

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8004)
