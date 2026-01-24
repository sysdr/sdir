// QuadTree implementation for spatial indexing
export class Point {
  constructor(x, y, data) {
    this.x = x;
    this.y = y;
    this.data = data;
  }
}

export class Rectangle {
  constructor(x, y, width, height) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }

  contains(point) {
    return (
      point.x >= this.x - this.width &&
      point.x <= this.x + this.width &&
      point.y >= this.y - this.height &&
      point.y <= this.y + this.height
    );
  }

  intersects(range) {
    return !(
      range.x - range.width > this.x + this.width ||
      range.x + range.width < this.x - this.width ||
      range.y - range.height > this.y + this.height ||
      range.y + range.height < this.y - this.height
    );
  }
}

export class QuadTree {
  constructor(boundary, capacity = 4) {
    this.boundary = boundary;
    this.capacity = capacity;
    this.points = [];
    this.divided = false;
    this.depth = 0;
  }

  subdivide() {
    const x = this.boundary.x;
    const y = this.boundary.y;
    const w = this.boundary.width / 2;
    const h = this.boundary.height / 2;

    const nw = new Rectangle(x - w, y - h, w, h);
    const ne = new Rectangle(x + w, y - h, w, h);
    const sw = new Rectangle(x - w, y + h, w, h);
    const se = new Rectangle(x + w, y + h, w, h);

    this.northwest = new QuadTree(nw, this.capacity);
    this.northeast = new QuadTree(ne, this.capacity);
    this.southwest = new QuadTree(sw, this.capacity);
    this.southeast = new QuadTree(se, this.capacity);

    this.northwest.depth = this.depth + 1;
    this.northeast.depth = this.depth + 1;
    this.southwest.depth = this.depth + 1;
    this.southeast.depth = this.depth + 1;

    this.divided = true;
  }

  insert(point) {
    if (!this.boundary.contains(point)) {
      return false;
    }

    if (this.points.length < this.capacity) {
      this.points.push(point);
      return true;
    }

    if (!this.divided) {
      this.subdivide();
    }

    return (
      this.northeast.insert(point) ||
      this.northwest.insert(point) ||
      this.southeast.insert(point) ||
      this.southwest.insert(point)
    );
  }

  query(range, found = []) {
    if (!this.boundary.intersects(range)) {
      return found;
    }

    for (const point of this.points) {
      if (range.contains(point)) {
        found.push(point);
      }
    }

    if (this.divided) {
      this.northwest.query(range, found);
      this.northeast.query(range, found);
      this.southwest.query(range, found);
      this.southeast.query(range, found);
    }

    return found;
  }

  getStats() {
    let maxDepth = this.depth;
    let nodeCount = 1;
    let pointCount = this.points.length;

    if (this.divided) {
      const nwStats = this.northwest.getStats();
      const neStats = this.northeast.getStats();
      const swStats = this.southwest.getStats();
      const seStats = this.southeast.getStats();

      maxDepth = Math.max(
        maxDepth,
        nwStats.maxDepth,
        neStats.maxDepth,
        swStats.maxDepth,
        seStats.maxDepth
      );
      nodeCount += nwStats.nodeCount + neStats.nodeCount + swStats.nodeCount + seStats.nodeCount;
      pointCount += nwStats.pointCount + neStats.pointCount + swStats.pointCount + seStats.pointCount;
    }

    return { maxDepth, nodeCount, pointCount };
  }
}
