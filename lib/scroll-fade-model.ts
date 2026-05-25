export interface ScrollFadeMetrics {
  clientWidth: number;
  scrollLeft: number;
  scrollWidth: number;
}

export function scrollFadeEdges(metrics: ScrollFadeMetrics) {
  const maxScroll = Math.max(0, metrics.scrollWidth - metrics.clientWidth);
  return {
    left: metrics.scrollLeft > 1,
    right: maxScroll - metrics.scrollLeft > 1,
  };
}
