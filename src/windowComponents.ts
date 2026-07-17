import type { Component } from 'svelte';
import ColorPickerTool from './components/ColorPickerTool.svelte';
import EncoderTool from './components/EncoderTool.svelte';
import HashTool from './components/HashTool.svelte';
import ImageConverterTool from './components/ImageConverterTool.svelte';
import JsonFormatter from './components/JsonFormatter.svelte';
import LuckyWheelTool from './components/LuckyWheelTool.svelte';
import PeekPCTool from './components/PeekPCTool.svelte';
import PythonFormatter from './components/PythonFormatter.svelte';
import TimerTool from './components/TimerTool.svelte';
import TranslatorTool from './components/TranslatorTool.svelte';
import type { WindowToolId } from './toolRegistry';

export const windowComponents: Record<WindowToolId, Component> = {
  json: JsonFormatter,
  python: PythonFormatter,
  encoder: EncoderTool,
  color: ColorPickerTool,
  hash: HashTool,
  image: ImageConverterTool,
  timer: TimerTool,
  translator: TranslatorTool,
  peek_pc: PeekPCTool,
  'lucky-wheel': LuckyWheelTool,
};
