from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class ProductView(BaseModel):
    id: int
    name: str
    description: Optional[str]
    price: float
    stock_quantity: int
    category: Optional[str]
    is_active: bool
    created_at: datetime
    last_updated: datetime

class OrderView(BaseModel):
    id: int
    customer_id: str
    product_id: int
    product_name: str
    quantity: int
    total_amount: float
    status: str
    created_at: datetime

class CustomerOrdersView(BaseModel):
    customer_id: str
    orders: List[OrderView]
    total_orders: int
    total_spent: float

class ProductStatsView(BaseModel):
    product_id: int
    product_name: str
    total_orders: int
    total_quantity_sold: int
    total_revenue: float
    current_stock: int
