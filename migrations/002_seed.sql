-- CharcoalX seed data. Matches the frontend catalog (lib/catalog.ts) exactly.
-- Activated carbon filters adsorb tar and particulate; this is harm reduction, not "safe smoking".

delete from orders;
delete from products;

insert into products (name, description, price_cents, stock, image_url) values
(
    'Classic Black',
    'Matte black activated charcoal tips, 20 per pack. Fits American Spirit and hand-rolled tobacco. The filter that started it all.',
    1299,
    200,
    '/images/image (7).png'
),
(
    'Natural',
    'Same activated carbon core, unbleached rice paper exterior. Cream finish for those who prefer a lighter aesthetic alongside their rolling papers.',
    1299,
    200,
    '/images/image (3).png'
),
(
    'Trio Sample',
    'Three filters before you commit to a full pack. Keep two, give one away. Comes in both Classic Black and Natural variants.',
    299,
    500,
    '/images/image (8).png'
),
(
    'Hemp Rolling Papers',
    'Slow-burning, unbleached hemp. 50 leaves per booklet, king size. No chalk, no additives. Pairs with any Charvo filter for a complete roll.',
    499,
    300,
    '/images/image (5).png'
),
(
    'Complete Rolling Kit',
    'Filters, hemp papers, herb grinder, rolling tray, and a storage vial — everything in a waxed canvas carry pouch. One purchase, nothing left to buy.',
    3499,
    50,
    '/images/image (4).png'
);
