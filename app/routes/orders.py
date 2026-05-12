from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.auth import get_current_user
from app.db import get_db
from app.models import Order, Product, User
from app.schemas import CreateOrderIn, OrderOut, OrderWithProductOut

router = APIRouter(prefix="/api/orders", tags=["orders"])


@router.post("", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
def create_order(
    body: CreateOrderIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Order:
    # Single transaction: SELECT FOR UPDATE → check stock → decrement → insert order.
    product = db.execute(
        select(Product).where(Product.id == body.product_id).with_for_update()
    ).scalar_one_or_none()

    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found")
    if product.stock < body.quantity:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Insufficient stock"
        )

    product.stock -= body.quantity
    order = Order(
        user_id=current_user.id,
        product_id=product.id,
        quantity=body.quantity,
        total_cents=product.price_cents * body.quantity,
        status="paid",
    )
    db.add(order)
    db.commit()
    db.refresh(order)
    return order


@router.get("/me", response_model=list[OrderWithProductOut])
def my_orders(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[Order]:
    rows = db.execute(
        select(Order)
        .where(Order.user_id == current_user.id)
        .options(selectinload(Order.product))
        .order_by(Order.created_at.desc())
    ).scalars()
    return list(rows)
