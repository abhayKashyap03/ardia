import assert from "node:assert/strict";
import { test } from "node:test";
import { TOOLBAR_ROWS, TOOLBAR_TRAILING, fieldInsetOf, toolbarTrailing } from "./toolbarRow.ts";
import { windowLength } from "./interfaceScale.ts";

const pinnedWidth = (row, count) => (count ? count * (row.extensionButton + TOOLBAR_TRAILING.itemGap) - TOOLBAR_TRAILING.itemGap : 0);

function inkGaps(row, count, split = false) {
  const t = toolbarTrailing(row, { pinnedWidth: pinnedWidth(row, count), split });
  const iconInset = (row.extensionButton - TOOLBAR_TRAILING.extensionIcon) / 2;
  const splitInset = (row.button - TOOLBAR_TRAILING.splitGlyph) / 2;
  const inks = [];
  if (split) {
    const right = t.splitRight + splitInset;
    inks.push([right, right + TOOLBAR_TRAILING.splitGlyph]);
    const second = t.splitRight + row.button + splitInset;
    inks.push([second, second + TOOLBAR_TRAILING.splitGlyph]);
  }
  for (let i = count - 1; i >= 0; i--) {
    const right = t.extensionsRight + (count - 1 - i) * (row.extensionButton + TOOLBAR_TRAILING.itemGap) + iconInset;
    inks.push([right, right + TOOLBAR_TRAILING.extensionIcon]);
  }
  const gaps = [];
  let edge = 0;
  for (const [right, left] of inks) {
    gaps.push(right - edge);
    edge = left;
  }
  gaps.push(t.fieldRight - edge);
  return { gaps, t };
}

const near = (a, b) => assert.ok(Math.abs(a - b) < 0.75, `${a} vs ${b}`);

for (const scale of [1, 1.25]) {
  for (const [name, row] of Object.entries(TOOLBAR_ROWS)) {
    test(`at ${scale * 100}% on the ${name} row, the address field alone sits as far from the card's trailing edge as from its top`, () => {
      const { t } = inkGaps(row, 0);
      assert.equal(windowLength(t.fieldRight, scale), windowLength(fieldInsetOf(row), scale));
    });

    for (const count of [1, 2, 3]) {
      test(`at ${scale * 100}% on the ${name} row with ${count} pinned, the extensions sit in a pill ${TOOLBAR_TRAILING.edge} pt from the edge, ${TOOLBAR_TRAILING.groupGap} pt from the field`, () => {
        const pinned = pinnedWidth(row, count);
        const t = toolbarTrailing(row, { pinnedWidth: pinned, split: false });
        assert.equal(t.groupRight, TOOLBAR_TRAILING.edge);
        assert.equal(t.extensionsRight - t.groupRight, TOOLBAR_TRAILING.groupPad);
        assert.equal(t.groupRight + t.groupWidth - (t.extensionsRight + pinned), TOOLBAR_TRAILING.groupPad);
        assert.equal(t.fieldRight - (t.groupRight + t.groupWidth), TOOLBAR_TRAILING.groupGap);
        assert.ok(windowLength(t.extensionsRight, scale) >= windowLength(TOOLBAR_TRAILING.edge, scale));
      });
    }

    test(`at ${scale * 100}% on the ${name} row in a split pane, the extension pill sits left of the Split buttons without overlapping them`, () => {
      for (const count of [1, 2]) {
        const t = toolbarTrailing(row, { pinnedWidth: pinnedWidth(row, count), split: true });
        assert.ok(t.groupRight >= t.splitRight + 2 * row.button);
        assert.equal(t.fieldRight - (t.groupRight + t.groupWidth), TOOLBAR_TRAILING.groupGap);
      }
      const { gaps, t } = inkGaps(row, 0, true);
      for (const gap of gaps.filter((_, i) => i !== 1)) near(gap, t.inkGap);
    });
  }
}

test("with nothing pinned there is no pill", () => {
  for (const row of Object.values(TOOLBAR_ROWS)) assert.equal(toolbarTrailing(row, { pinnedWidth: 0, split: false }).groupWidth, 0);
});

test("when the card's corner is rounder than the field's, the lone field steps in until its corner keeps the top inset from the card's arc", () => {
  const compact = TOOLBAR_ROWS.compact;
  const regular = TOOLBAR_ROWS.regular;
  const alone = (row, cardRadius) => toolbarTrailing(row, { pinnedWidth: 0, split: false, cardRadius }).fieldRight;
  assert.equal(alone(regular, 10), fieldInsetOf(regular));
  assert.equal(alone(compact, 10), fieldInsetOf(compact));
  for (const [row, cardRadius] of [[regular, 10], [regular, 18], [compact, 10], [compact, 6]]) {
    const right = alone(row, cardRadius);
    const top = fieldInsetOf(row);
    const dx = cardRadius - right - row.fieldRadius;
    const dy = cardRadius - top - row.fieldRadius;
    const closest = dx > 0 && dy > 0 ? cardRadius - Math.hypot(dx, dy) - row.fieldRadius : Math.min(top, right);
    assert.ok(closest >= top - 1e-9, `${closest} < ${top}`);
    assert.ok(right <= Math.max(top, cardRadius - row.fieldRadius) + 1e-9);
  }
});
