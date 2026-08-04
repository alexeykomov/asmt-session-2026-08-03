goog.provide('funwithactivity.charts.geometry');


/**
 * @fileoverview Pure chart arithmetic, deliberately separated from anything
 * that touches the DOM.
 *
 * A wrong chart still looks like a chart. A bar scaled by the wrong divisor
 * or a pie whose slices quietly overlap renders without an error and reads as
 * plausible — unlike a blank screen, nothing about it announces the failure.
 * The only defence is to compute the geometry somewhere it can be asserted
 * exactly, which is why these functions take numbers and return numbers and
 * know nothing about SVG.
 *
 * Mirrored by FWAChartGeometry on iOS and ChartGeometry on Android so the
 * three platforms cannot disagree about where a bar ends.
 */


/**
 * Upper bound of the value axis.
 *
 * Rounded up to a "nice" number so the axis reads 10,000 rather than 9,412,
 * and never zero: an all-zero series must still produce a usable divisor
 * rather than a division by zero that renders every bar as NaN.
 * @param {!Array<number>} values
 * @return {number} Strictly positive.
 */
funwithactivity.charts.geometry.axisMax = function(values) {
  let max = 0;
  for (let i = 0; i < values.length; i++) {
    if (values[i] > max) max = values[i];
  }
  if (max <= 0) return 1;

  // Round up to 1, 2 or 5 times a power of ten — the standard set of tick
  // steps that produce readable axis labels at any magnitude.
  const magnitude = Math.pow(10, Math.floor(Math.log(max) / Math.LN10));
  const normalised = max / magnitude;
  let step;
  if (normalised <= 1) step = 1;
  else if (normalised <= 2) step = 2;
  else if (normalised <= 5) step = 5;
  else step = 10;
  return step * magnitude;
};


/**
 * Height in pixels of a bar for `value` in a plot area `plotHeight` tall.
 *
 * Linear in value, which is the property the tests pin: a bar for twice the
 * value must be exactly twice as tall, or the chart misleads while looking
 * entirely normal.
 * @param {number} value
 * @param {number} axisMax Must be > 0 — see axisMax().
 * @param {number} plotHeight
 * @return {number} Clamped to [0, plotHeight].
 */
funwithactivity.charts.geometry.barHeight = function(
    value, axisMax, plotHeight) {
  if (!(axisMax > 0)) return 0;
  const h = (value / axisMax) * plotHeight;
  if (!isFinite(h) || h < 0) return 0;
  return Math.min(h, plotHeight);
};


/**
 * Sweep angles in degrees for a pie, one per value, in input order.
 *
 * The angles always total exactly 360: the last slice takes the remainder
 * rather than its own rounded share, because a pie that leaves a hairline gap
 * — or overlaps itself by a fraction of a degree — is visibly wrong and
 * cannot be fixed by rounding differently.
 *
 * An empty or all-zero input returns an empty array rather than a full circle
 * of nothing; the caller renders its "no data" state instead.
 * @param {!Array<number>} values
 * @return {!Array<number>}
 */
funwithactivity.charts.geometry.pieAngles = function(values) {
  let total = 0;
  for (let i = 0; i < values.length; i++) {
    if (values[i] > 0) total += values[i];
  }
  if (total <= 0) return [];

  const angles = [];
  let assigned = 0;
  for (let i = 0; i < values.length; i++) {
    const value = values[i] > 0 ? values[i] : 0;
    let sweep;
    if (i === values.length - 1) {
      sweep = 360 - assigned;
    } else {
      sweep = (value / total) * 360;
      assigned += sweep;
    }
    angles.push(sweep);
  }
  return angles;
};


/**
 * A point on a circle, for pie slice edges.
 *
 * Angles are measured clockwise from twelve o'clock, which is where every
 * reader expects a pie to start. SVG's own angle convention starts at three
 * o'clock and runs anticlockwise, so the -90° rotation happens here, once,
 * rather than in each caller.
 * @param {number} cx
 * @param {number} cy
 * @param {number} radius
 * @param {number} degrees
 * @return {{x: number, y: number}}
 */
funwithactivity.charts.geometry.pointOnCircle = function(
    cx, cy, radius, degrees) {
  const radians = (degrees - 90) * Math.PI / 180;
  return {
    x: cx + radius * Math.cos(radians),
    y: cy + radius * Math.sin(radians),
  };
};


/**
 * Left offset and width for one bar in a grouped bar chart.
 *
 * Bars within a group sit flush against each other and the group is centred
 * in its category slot, so the gap a reader sees between groups is real
 * whitespace rather than a coincidence of rounding.
 * @param {number} categoryIndex
 * @param {number} seriesIndex
 * @param {number} seriesCount
 * @param {number} slotWidth Width of one category slot.
 * @param {number} groupPadding Whitespace either side of the group.
 * @return {{x: number, width: number}}
 */
funwithactivity.charts.geometry.groupedBarSlot = function(
    categoryIndex, seriesIndex, seriesCount, slotWidth, groupPadding) {
  const usable = Math.max(slotWidth - groupPadding * 2, 1);
  const width = usable / Math.max(seriesCount, 1);
  return {
    x: categoryIndex * slotWidth + groupPadding + seriesIndex * width,
    width: width,
  };
};
