'use strict';

const assert = require('assert');
const {loadChartGeometry} = require('./helpers/load-chart-geometry');

const G = loadChartGeometry();

describe('chart geometry', () => {
  describe('axisMax', () => {
    it('rounds up to a readable tick, never below the data', () => {
      assert.ok(G.axisMax([9412]) >= 9412);
      assert.equal(G.axisMax([9412]), 10000);
      assert.equal(G.axisMax([42]), 50);
      assert.equal(G.axisMax([0.4]), 0.5);
    });

    // An all-zero series is a real case (a rest day, a provider with nothing
    // to report). Returning 0 would make every bar height a division by zero
    // and render the whole chart as NaN.
    it('never returns zero', () => {
      assert.ok(G.axisMax([]) > 0);
      assert.ok(G.axisMax([0, 0, 0]) > 0);
      assert.ok(G.axisMax([-5]) > 0);
    });
  });

  describe('barHeight', () => {
    // The invariant that matters: a bar for twice the value must be exactly
    // twice as tall. A chart that breaks this misleads while looking normal.
    it('is linear in value', () => {
      const max = 100;
      const plot = 200;
      assert.equal(G.barHeight(50, max, plot), 100);
      assert.equal(G.barHeight(25, max, plot), 50);
      assert.equal(G.barHeight(100, max, plot), 200);
      assert.equal(
          G.barHeight(60, max, plot), 2 * G.barHeight(30, max, plot));
    });

    it('clamps rather than overflowing the plot area', () => {
      assert.equal(G.barHeight(150, 100, 200), 200);
    });

    it('is zero for a zero or negative value', () => {
      assert.equal(G.barHeight(0, 100, 200), 0);
      assert.equal(G.barHeight(-10, 100, 200), 0);
    });

    it('is zero rather than NaN when the axis is degenerate', () => {
      assert.equal(G.barHeight(10, 0, 200), 0);
    });
  });

  describe('pieAngles', () => {
    // A pie that leaves a hairline gap, or overlaps itself by a fraction of
    // a degree, is visibly wrong and cannot be fixed by rounding differently.
    it('always totals exactly 360', () => {
      for (const values of [
        [25, 25, 25, 25],
        [22.4, 51.3, 18.1, 8.2],
        [1, 1, 1],
        [99, 1],
        [7],
      ]) {
        const total = G.pieAngles(values).reduce((a, b) => a + b, 0);
        assert.equal(total, 360, 'values ' + JSON.stringify(values));
      }
    });

    it('is proportional to the values', () => {
      const angles = G.pieAngles([25, 75]);
      assert.equal(angles[0], 90);
      assert.equal(angles[1], 270);
    });

    it('returns nothing to draw for empty or all-zero input', () => {
      assert.deepEqual(G.pieAngles([]), []);
      assert.deepEqual(G.pieAngles([0, 0]), []);
    });

    it('ignores negative values rather than sweeping backwards', () => {
      const angles = G.pieAngles([50, -10, 50]);
      assert.equal(angles.reduce((a, b) => a + b, 0), 360);
      assert.ok(angles.every((a) => a >= 0));
    });
  });

  describe('pointOnCircle', () => {
    // Zero degrees must be twelve o'clock: SVG's own convention starts at
    // three o'clock, and getting this wrong rotates every pie by 90° while
    // still producing a perfectly plausible-looking chart.
    it('measures clockwise from twelve o\'clock', () => {
      const top = G.pointOnCircle(100, 100, 50, 0);
      assert.ok(Math.abs(top.x - 100) < 1e-9);
      assert.ok(Math.abs(top.y - 50) < 1e-9);

      const right = G.pointOnCircle(100, 100, 50, 90);
      assert.ok(Math.abs(right.x - 150) < 1e-9);
      assert.ok(Math.abs(right.y - 100) < 1e-9);
    });
  });

  describe('groupedBarSlot', () => {
    it('packs a group into its slot without overlapping the next', () => {
      const slotWidth = 90;
      const padding = 10;
      const a = G.groupedBarSlot(0, 0, 3, slotWidth, padding);
      const b = G.groupedBarSlot(0, 1, 3, slotWidth, padding);
      const c = G.groupedBarSlot(0, 2, 3, slotWidth, padding);

      // Contiguity, within floating-point tolerance: the implementation
      // computes each offset from the index while this accumulates, so the
      // two differ in the last bit. Exact equality would make the test
      // fragile without making the chart any more correct.
      const close = (x, y) => assert.ok(Math.abs(x - y) < 1e-9,
          x + ' is not adjacent to ' + y);

      close(a.x, padding);
      close(b.x, a.x + a.width);
      close(c.x, b.x + b.width);
      assert.ok(c.x + c.width <= slotWidth - padding + 1e-9);
    });

    it('offsets each category by a whole slot', () => {
      const first = G.groupedBarSlot(0, 0, 2, 80, 8);
      const second = G.groupedBarSlot(1, 0, 2, 80, 8);
      assert.equal(second.x - first.x, 80);
    });

    it('produces a positive width for a single series', () => {
      const only = G.groupedBarSlot(0, 0, 1, 60, 6);
      assert.ok(only.width > 0);
    });
  });
});
