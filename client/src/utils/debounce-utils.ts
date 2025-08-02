/**
 * Debounce utilities for chart performance optimization
 * Reduces event frequency during rapid mouse movement while maintaining responsiveness
 */

export const DEFAULT_HOVER_DEBOUNCE_DELAY = 40;

export interface DebounceState {
  timeoutId: number | null;
  lastMonitorId: number | null;
  isPending: boolean;
  eventCount: number;
}

export interface DebouncedFunction {
  debounce: (callback: () => void, monitorId?: number | null) => void;
  cancel: () => void;
  isHovering: () => boolean;
  getCurrentMonitorId: () => number | null;
  getEventCount: () => number;
  reset: () => void;
}

/**
 * Create a debouncer for mouse hover events with state tracking
 */
export function createHoverDebouncer(delay: number = DEFAULT_HOVER_DEBOUNCE_DELAY): DebouncedFunction {
  const state: DebounceState = {
    timeoutId: null,
    lastMonitorId: null,
    isPending: false,
    eventCount: 0
  };

  const debounce = (callback: () => void, monitorId?: number | null): void => {
    const startTime = performance.now();
    state.eventCount++;

    // Cancel any pending callback
    if (state.timeoutId) {
      clearTimeout(state.timeoutId);
    }

    // Check if this is the same monitor we're already targeting
    if (state.isPending && state.lastMonitorId === monitorId) {
      console.log('🎯 Debouncer: Skipping redundant operation', {
        monitorId,
        eventCount: state.eventCount,
        timestamp: startTime
      });
      return;
    }

    // Update target monitor (this allows smooth A->B transitions)
    const previousMonitorId = state.lastMonitorId;
    state.lastMonitorId = monitorId ?? null;
    state.isPending = true;

    console.log('🎯 Debouncer: Scheduling transition', {
      from: previousMonitorId,
      to: monitorId,
      delay,
      eventCount: state.eventCount,
      timestamp: startTime
    });

    state.timeoutId = window.setTimeout(() => {
      const executeTime = performance.now();
      console.log('🎯 Debouncer: Executing transition', {
        from: previousMonitorId,
        to: state.lastMonitorId,
        totalDelay: executeTime - startTime,
        eventCount: state.eventCount,
        timestamp: executeTime
      });

      callback();
      state.isPending = false;
      state.timeoutId = null;
    }, delay);
  };

  const cancel = (): void => {
    if (state.timeoutId) {
      clearTimeout(state.timeoutId);
      state.timeoutId = null;
    }
    state.isPending = false;
    console.log('🎯 Debouncer: Cancelled', {
      lastMonitorId: state.lastMonitorId,
      eventCount: state.eventCount
    });
  };

  const isHovering = (): boolean => state.isPending;

  const getCurrentMonitorId = (): number | null => state.lastMonitorId;

  const getEventCount = (): number => state.eventCount;

  const reset = (): void => {
    cancel();
    state.lastMonitorId = null;
    state.eventCount = 0;
    console.log('🎯 Debouncer: Reset');
  };

  return {
    debounce,
    cancel,
    isHovering,
    getCurrentMonitorId,
    getEventCount,
    reset
  };
}

/**
 * Global hover state manager to coordinate between chart and table events
 */
class HoverStateManager {
  private currentMonitorId: number | null = null;
  private eventSource: 'chart' | 'table' | null = null;
  private listeners: Set<(monitorId: number | null, source: 'chart' | 'table' | null) => void> = new Set();

  setHover(monitorId: number | null, source: 'chart' | 'table'): void {
    // Only update if actually changing
    if (this.currentMonitorId === monitorId && this.eventSource === source) {
      return;
    }

    const prevMonitorId = this.currentMonitorId;
    const prevSource = this.eventSource;

    this.currentMonitorId = monitorId;
    this.eventSource = monitorId ? source : null;

    console.log('🎯 HoverState: Update', {
      from: { monitorId: prevMonitorId, source: prevSource },
      to: { monitorId, source: this.eventSource }
    });

    // Notify all listeners
    this.listeners.forEach(listener => {
      listener(this.currentMonitorId, this.eventSource);
    });
  }

  getCurrentMonitorId(): number | null {
    return this.currentMonitorId;
  }

  getCurrentSource(): 'chart' | 'table' | null {
    return this.eventSource;
  }

  isHovering(monitorId: number): boolean {
    return this.currentMonitorId === monitorId;
  }

  addListener(listener: (monitorId: number | null, source: 'chart' | 'table' | null) => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: (monitorId: number | null, source: 'chart' | 'table' | null) => void): void {
    this.listeners.delete(listener);
  }

  reset(): void {
    this.currentMonitorId = null;
    this.eventSource = null;
    console.log('🎯 HoverState: Reset');
  }
}

// Global instance for coordinating hover state across the chart
export const globalHoverState = new HoverStateManager();
