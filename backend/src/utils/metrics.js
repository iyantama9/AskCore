const counters = new Map();
const histograms = new Map();

function keyFor(name, labels = {}) {
  return JSON.stringify({ name, labels });
}

function inc(name, labels = {}, amount = 1) {
  const key = keyFor(name, labels);
  counters.set(key, (counters.get(key) || 0) + amount);
}

function observe(name, value, labels = {}) {
  const key = keyFor(name, labels);
  const current = histograms.get(key) || {
    count: 0,
    sum: 0,
    min: Number.POSITIVE_INFINITY,
    max: 0,
  };
  current.count += 1;
  current.sum += value;
  current.min = Math.min(current.min, value);
  current.max = Math.max(current.max, value);
  histograms.set(key, current);
}

function snapshot() {
  return {
    counters: Array.from(counters.entries()).map(([key, value]) => ({
      ...JSON.parse(key),
      value,
    })),
    histograms: Array.from(histograms.entries()).map(([key, value]) => ({
      ...JSON.parse(key),
      count: value.count,
      sum: Number(value.sum.toFixed(3)),
      min: Number(value.min.toFixed(3)),
      max: Number(value.max.toFixed(3)),
      avg: Number((value.sum / value.count).toFixed(3)),
    })),
  };
}

module.exports = { inc, observe, snapshot };
