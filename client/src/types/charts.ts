/**
 * Type definitions for chart components and configurations
 */

import type * as d3 from 'd3';

export interface ChartDimensions {
  width: number;
  height: number;
  padding: {
    horizontal: number;
    vertical: number;
  };
}

export interface ChartColors {
  offset: {
    good: string;
    warning: string;
    error: string;
  };
  score: {
    good: string;
    warning: string;
    error: string;
  };
  lines: {
    registered: string;
    active: string;
    inactive: string;
    totalScore: string;
  };
  grid: string;
  zeroLine: string;
}

export interface ChartThresholds {
  offset: {
    good: number;
    warning: number;
    max: number;
    min: number;
  };
  score: {
    max: number;
    min: number;
  };
}

export interface ChartDefaults {
  padding: {
    horizontal: number;
    vertical: number;
  };
  dimensions: {
    defaultWidth: number;
    defaultHeight: number;
    widthRatio: number;
  };
  ticks: {
    x: number;
    y: number;
  };
}

export interface MonitorStatusConfig {
  order: number;
  class: string;
  label: string;
}

export interface ServerChartOptions {
  legend?: Element | null;
  showTooltips?: boolean;
  responsive?: boolean;
}

export interface ZoneChartOptions {
  ipVersion?: 'v4' | 'v6';
  name?: string;
  showBothVersions?: boolean;
}

/**
 * D3 scale types used in charts
 */
export type TimeScale = d3.ScaleTime<number, number>;
export type LinearScale = d3.ScaleLinear<number, number>;
export type PowerScale = d3.ScalePower<number, number>;
export type SvgSelection = d3.Selection<SVGSVGElement, unknown, null, undefined>;
export type GSelection = d3.Selection<SVGGElement, unknown, null, undefined>;

/**
 * Chart creation result
 */
export interface ChartElements {
  svg: SvgSelection;
  g: GSelection;
}
