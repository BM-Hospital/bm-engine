# Third-party notices

bm-engine is a Zig port of [takumi](https://github.com/kane50613/takumi) (Copyright (c) 2025 Kane Wang,
MIT OR Apache-2.0). The npm package contains JavaScript wrappers and WebAssembly binaries compiled from
bm-engine's Zig sources. Parts of those sources are transliterations of takumi code that itself follows
Chromium / Blink, Skia and other projects, or follow third-party algorithms and data directly. This file
carries the notices those sources require. No third-party font files are distributed.

1. Chromium (Blink) and Skia: BSD-style licenses (takumi's `LICENSE-CHROMIUM`, verbatim)
2. tiny-skia: BSD 3-Clause
3. HarfBuzz: "Old MIT" license
4. libwebp: BSD 3-Clause
5. Independent JPEG Group (libjpeg)
6. Unicode data and algorithms (UCD, emoji-data, ICU / ICU4X): Unicode License V3
7. emoji-segmenter: Apache License 2.0
8. Brotli: MIT
9. Taffy: MIT

## 1. Chromium (Blink) and Skia

bm-engine's layout (LayoutUnit arithmetic, inline line boxes, tables, floats), border / outline /
decoration painting, table painting, font selection and fallback, colour helpers, dash fitting, the
Gaussian blur (`src/raster/blur.zig`, Skia `SkBlurEngine`), the HTML UA styles and related code are ports
of the takumi-core parts listed below (the list names takumi's Rust files). The following text is
takumi's `takumi-core/LICENSE-CHROMIUM`, reproduced verbatim.

```text
Parts of takumi-core follow algorithms from Chromium's Blink renderer and the
Skia library it draws with. Each part names its source below, followed by the
notice that source carries.

1. The dash and dot spacing in src/layout/border.rs (`BorderStyle::dash_pattern`,
   `square_dash`, and `select_best_dash_gap`), from
   third_party/blink/renderer/platform/graphics/styled_stroke_data.cc, and
   `FixedPoint`, `LayoutUnit`, `TextRunLayoutUnit`, and `InlineLayoutUnit` in
   src/layout_unit.rs, from
   third_party/blink/renderer/platform/geometry/layout_unit.h, and
   `FontFace::get_font_selection_capabilities` in src/fonts/font_face.rs, from
   third_party/blink/renderer/core/css/font_face.cc, and
   `FontCustomPlatformData` and `FontPlatformData` in
   src/fonts/font_custom_platform_data.rs, from
   third_party/blink/renderer/platform/fonts/font_custom_platform_data.cc and
   third_party/blink/renderer/platform/fonts/font_platform_data.h.

Copyright (c) 2012, Google Inc. All rights reserved.
Copyright (C) 2013 Google Inc. All rights reserved.
Copyright (C) 2007 Apple Computer, Inc.
Copyright (c) 2006, 2007, 2008, 2009, Google Inc. All rights reserved.
Copyright (C) 2010 Company 100, Inc.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


2. `Color::dark` and `Color::light` in src/style/properties/color.rs, from
   third_party/blink/renderer/platform/graphics/color.cc, and
   `FontDataForRangeSet` in src/fonts/font_data_for_range_set.rs, from
   third_party/blink/renderer/platform/fonts/font_data_for_range_set.h, and
   `FontData::font_data_for_character` in src/fonts/font_fallback_list.rs, from
   third_party/blink/renderer/platform/fonts/segmented_font_data.cc, and
   `SimpleFontData::small_caps_font_data` in src/fonts/simple_font_data.rs, from
   third_party/blink/renderer/platform/fonts/simple_font_data.cc, and
   `FontFaceCache` in src/fonts/font_face_cache.rs, `CssSegmentedFontFace` in
   src/fonts/css_segmented_font_face.rs, `FontFace::get_font_data` in
   src/fonts/font_face.rs, and `CssFontSelector::get_font_data` in
   src/fonts/css_font_selector.rs, from
   third_party/blink/renderer/core/css/font_face_cache.cc,
   third_party/blink/renderer/core/css/css_segmented_font_face.cc,
   third_party/blink/renderer/core/css/css_font_face.cc, and
   third_party/blink/renderer/core/css/css_font_selector.cc.

Copyright (C) 2003, 2004, 2005, 2006, 2008, 2009 Apple Inc. All rights reserved.
Copyright (C) 2007, 2008, 2011 Apple Inc. All rights reserved.
          (C) 2007, 2008 Nikolas Zimmermann <zimmermann@kde.org>
Copyright (C) 2013 Google Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


3. `Color::inset_outset` in src/style/properties/color.rs, `BorderShape`,
   `Miter`, `StyledLine` and the side order in src/painter/border.rs,
   `BoxSideRect` in src/painter/box_side.rs, `OutlineIsland::paint`
   and `ComplexOutline` in src/painter/outline.rs, `RightAngleContour` in
   src/layout/inline/outline.rs, the decoration lines in
   src/painter/decoration.rs, the property rules in src/paint_property.rs,
   `ConversionContext` in src/paint_chunk.rs, the corners and side clips
   in src/layout/contoured_rect.rs, the table layout in src/layout/table/,
   the table painting in src/painter/table.rs, the background layer geometry in
   src/layout/background_image_geometry.rs, and the line box alignment in
   src/layout/inline/line_box.rs, from
   third_party/blink/renderer/core/paint/box_border_painter.cc,
   third_party/blink/renderer/core/paint/outline_painter.cc,
   third_party/blink/renderer/core/paint/decoration_line_painter.cc,
   third_party/blink/renderer/core/paint/text_decoration_info.cc,
   third_party/blink/renderer/core/paint/text_painter.cc,
   third_party/blink/renderer/core/paint/paint_property_tree_builder.cc,
   third_party/blink/renderer/core/paint/contoured_border_geometry.cc,
   third_party/blink/renderer/platform/geometry/contoured_rect.cc,
   third_party/blink/renderer/core/paint/background_image_geometry.cc,
   third_party/blink/renderer/core/paint/box_painter_base.cc,
   third_party/blink/renderer/core/paint/table_painters.cc,
   third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc,
   third_party/blink/renderer/core/layout/table/table_section_layout_algorithm.cc,
   third_party/blink/renderer/core/layout/table/table_row_layout_algorithm.cc,
   third_party/blink/renderer/core/layout/table/table_layout_utils.cc,
   third_party/blink/renderer/core/layout/table/table_layout_algorithm_types.cc,
   third_party/blink/renderer/core/layout/table/table_borders.cc,
   third_party/blink/renderer/core/layout/table/table_node.cc,
   third_party/blink/renderer/core/layout/table/layout_table_column_visitor.h,
   third_party/blink/renderer/core/layout/table/table_fragment_data.h,
   third_party/blink/renderer/core/layout/inline/inline_box_state.cc,
   third_party/blink/renderer/platform/geometry/path_builder.cc,
   third_party/blink/renderer/platform/graphics/compositing/paint_chunks_to_cc_layer.cc;
   and `HarfBuzzRunGlyphData` in src/fonts/shaping/glyph_data.rs and
   `GlyphDataRange` in src/fonts/shaping/glyph_data_range.rs, from
   third_party/blink/renderer/platform/fonts/shaping/glyph_data.h and
   third_party/blink/renderer/platform/fonts/shaping/glyph_data_range.cc;
   and `ScriptRunIterator` in src/fonts/script_run_iterator.rs,
   `SymbolsIterator` in src/fonts/symbols_iterator.rs, `FontFallbackPriority`
   in src/fonts/font_fallback_priority.rs, `RunSegmenter` in
   src/fonts/shaping/run_segmenter.rs, and `EmojiSegmentationCategory` in
   src/text/emoji_segmentation_category.rs, from
   third_party/blink/renderer/platform/fonts/script_run_iterator.cc,
   third_party/blink/renderer/platform/fonts/symbols_iterator.cc,
   third_party/blink/renderer/platform/fonts/font_fallback_priority.h,
   third_party/blink/renderer/platform/fonts/shaping/run_segmenter.cc, and
   third_party/blink/renderer/platform/text/emoji_segmentation_category_inline_header.h;
   and `FontFallbackIterator` in src/fonts/font_fallback_iterator.rs and
   `ShapeResultView` in src/fonts/shaping/shape_result_view.rs, from
   third_party/blink/renderer/platform/fonts/font_fallback_iterator.cc and
   third_party/blink/renderer/platform/fonts/shaping/shape_result_view.cc;
   and `ShapeResultSpacing` in src/fonts/shaping/shape_result_spacing.rs and
   `JustificationContext` in src/text/justification_opportunity.rs, from
   third_party/blink/renderer/platform/fonts/shaping/shape_result_spacing.cc and
   third_party/blink/renderer/platform/text/justification_opportunity.cc;
   and `ShapingLineBreaker` in src/fonts/shaping/shaping_line_breaker.rs, from
   third_party/blink/renderer/platform/fonts/shaping/shaping_line_breaker.cc;
   and `InlineItem` in src/layout/inline/inline_item.rs, `InlineItemsBuilder`
   in src/layout/inline/inline_items_builder.rs, `collect_inlines` in
   src/layout/inline/inline_node.rs, `InlineItemSegments` in
   src/layout/inline/inline_item_segment.rs, `InlineNodeData` in
   src/layout/inline/inline_node_data.rs, `BidiParagraph` in
   src/text/bidi_paragraph.rs, the marker margins and `width_of_symbol` in
   src/layout/list_marker.rs, `LineBreaker` in src/layout/inline/line_breaker.rs,
   `LineInfo` in src/layout/inline/line_info.rs, `InlineItemResult` and
   `HyphenResult` in src/layout/inline/inline_item_result.rs, `InlineBreakToken`
   in src/layout/inline/inline_break_token.rs, `LineBreakPoint` in
   src/layout/inline/line_break_point.rs, `InlineItemTextIndex` in
   src/layout/inline/inline_item_text_index.rs, the exclusions in
   src/layout/exclusions/, `BfcOffset` and `BfcRect` in src/layout/bfc_rect.rs,
   the float placement in src/layout/floats_utils.rs, `InlineBoxState` and
   `InlineLayoutStateStack` in src/layout/inline/inline_box_state.rs,
   `LogicalLineBuilder` in src/layout/inline/logical_line_builder.rs,
   `LogicalLineItem` in src/layout/inline/logical_line_item.rs, `FontHeight` in
   src/fonts/font_height.rs, `compute_relative_offset_for_inline` in
   src/layout/relative_utils.rs, the logical geometry in
   src/layout/logical_rect.rs, `LayoutResult::baseline_metrics` in
   src/layout/inline/inline_item_result.rs, `InlineLayoutAlgorithm` and
   `TextAlign::line_offset_for_text_align` in
   src/layout/inline/inline_layout_algorithm.rs, the justification in
   src/layout/inline/justification_utils.rs, `LeadingFloats` in
   src/layout/inline/leading_floats.rs, `InlineChildLayoutContext` in
   src/layout/inline/inline_child_layout_context.rs, `LineTruncator` in
   src/layout/inline/line_truncator.rs, `MinMaxSizes` and
   `InlineNode::compute_min_max_sizes` in src/layout/inline/min_max_sizes.rs,
   `ScoreLineBreaker` and `ScoreLineBreakContext` in
   src/layout/inline/score_line_breaker.rs, the bisection in
   src/layout/inline/paragraph_line_breaker.rs, `LineBreakCandidate` in
   src/layout/inline/line_break_candidate.rs, `LineWidths` in
   src/layout/inline/line_widths.rs, the line clamp in
   src/layout/constraint_space.rs, `capitalize` in src/text/capitalize.rs,
   `CaseMap` in src/text/case_map.rs, `SmallCapsIterator` in
   src/fonts/small_caps_iterator.rs, `OpenTypeCapsSupport` in
   src/fonts/open_type_caps_support.rs, `CaseMapIntend::fill_buffer` in
   src/fonts/shaping/case_mapping_harfbuzz_buffer_filler.rs, `LineFitter` and the
   `text-fit` scales in src/layout/inline/text_fit_utils.rs and
   src/layout/inline/text_fit_scale.rs, and the `white-space` predicates in
   src/style/properties/mod.rs and src/style/properties/text_wrap.rs, from
   third_party/blink/renderer/core/layout/inline/inline_item.cc,
   third_party/blink/renderer/core/layout/inline/inline_items_builder.cc,
   third_party/blink/renderer/core/layout/inline/inline_node.cc,
   third_party/blink/renderer/core/layout/inline/inline_item_segment.cc,
   third_party/blink/renderer/core/layout/inline/inline_node_data.h,
   third_party/blink/renderer/platform/text/bidi_paragraph.cc,
   third_party/blink/renderer/core/layout/list/list_marker.cc,
   third_party/blink/renderer/core/layout/inline/line_breaker.cc,
   third_party/blink/renderer/core/layout/inline/line_info.cc,
   third_party/blink/renderer/core/layout/inline/inline_item_result.cc,
   third_party/blink/renderer/core/layout/inline/hyphen_result.cc,
   third_party/blink/renderer/core/layout/inline/inline_break_token.h,
   third_party/blink/renderer/core/layout/inline/line_break_point.h,
   third_party/blink/renderer/core/layout/inline/inline_item_text_index.h,
   third_party/blink/renderer/core/layout/exclusions/exclusion_space.cc,
   third_party/blink/renderer/core/layout/exclusions/exclusion_area.h,
   third_party/blink/renderer/core/layout/exclusions/layout_opportunity.cc,
   third_party/blink/renderer/core/layout/exclusions/line_layout_opportunity.h,
   third_party/blink/renderer/core/layout/geometry/bfc_rect.h,
   third_party/blink/renderer/core/layout/floats_utils.cc,
   third_party/blink/renderer/core/layout/unpositioned_float.h,
   third_party/blink/renderer/core/layout/positioned_float.h,
   third_party/blink/renderer/core/layout/inline/logical_line_builder.cc,
   third_party/blink/renderer/core/layout/inline/logical_line_item.cc,
   third_party/blink/renderer/core/layout/inline/inline_items_data.cc,
   third_party/blink/renderer/platform/fonts/font_height.h,
   third_party/blink/renderer/core/layout/relative_utils.cc,
   third_party/blink/renderer/core/layout/geometry/logical_rect.h,
   third_party/blink/renderer/core/layout/logical_box_fragment.cc,
   third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc,
   third_party/blink/renderer/core/layout/inline/justification_utils.cc,
   third_party/blink/renderer/core/layout/inline/leading_floats.h,
   third_party/blink/renderer/core/layout/inline/inline_child_layout_context.cc,
   third_party/blink/renderer/core/layout/length_utils.cc,
   third_party/blink/renderer/core/layout/inline/line_truncator.cc,
   third_party/blink/renderer/core/layout/min_max_sizes.h,
   third_party/blink/renderer/core/layout/inline/score_line_breaker.cc,
   third_party/blink/renderer/core/layout/inline/score_line_break_context.h,
   third_party/blink/renderer/core/layout/inline/paragraph_line_breaker.cc,
   third_party/blink/renderer/core/layout/inline/line_break_candidate.cc,
   third_party/blink/renderer/core/layout/inline/line_widths.cc,
   third_party/blink/renderer/core/layout/line_clamp_data.h,
   third_party/blink/renderer/platform/text/capitalize.cc,
   third_party/blink/renderer/platform/wtf/text/case_map.cc,
   third_party/blink/renderer/platform/fonts/small_caps_iterator.cc,
   third_party/blink/renderer/platform/fonts/opentype/open_type_caps_support.cc,
   third_party/blink/renderer/platform/fonts/shaping/case_mapping_harfbuzz_buffer_filler.cc,
   third_party/blink/renderer/core/layout/inline/text_fit_utils.cc,
   third_party/blink/renderer/core/layout/inline/text_fit_scale.h, and
   third_party/blink/renderer/core/css/white_space.h;
   and `VariableFontSubType::probe_variable_font` in
   src/fonts/font_custom_platform_data.rs and the tests in
   src/fonts/font_selection_types.rs and src/fonts/font_face_cache.rs, from
   third_party/blink/renderer/platform/fonts/opentype/font_format_check.cc,
   third_party/blink/renderer/platform/fonts/font_selection_types_test.cc, and
   third_party/blink/renderer/core/css/font_face_cache_test.cc.

Copyright 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2023, 2024, 2025 The Chromium Authors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


4. `skips_ink` and its character tables in src/layout/intercept.rs, and the
   predicates in src/text/character.rs, from
   third_party/blink/renderer/platform/text/character.h,
   third_party/blink/renderer/platform/text/character.cc,
   third_party/blink/renderer/platform/text/character_emoji.cc, and
   third_party/blink/renderer/platform/text/character_property_data.h.

Copyright (C) 2014 Google Inc. All rights reserved.
Copyright 2015, 2016 The Chromium Authors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

5. The Gaussian blur passes in src/blur.rs, from Skia's src/core/SkBlurEngine.cpp.

Copyright (c) 2011 Google Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


6. `ShapeResult` in src/fonts/shaping/shape_result.rs, `ShapeResultRun` in
   src/fonts/shaping/shape_result_run.rs, and `HarfBuzzShaper` in
   src/fonts/shaping/harfbuzz_shaper.rs, from
   third_party/blink/renderer/platform/fonts/shaping/shape_result.cc,
   third_party/blink/renderer/platform/fonts/shaping/shape_result.h,
   third_party/blink/renderer/platform/fonts/shaping/shape_result_run.h, and
   third_party/blink/renderer/platform/fonts/shaping/harfbuzz_shaper.cc.

Copyright (c) 2012 Google Inc. All rights reserved.
Copyright (C) 2013 BlackBerry Limited. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


7. `FontFallbackList` in src/fonts/font_fallback_list.rs, from
   third_party/blink/renderer/platform/fonts/font_fallback_list.cc, and
   `FontSelectionDescription::merge_font_variation_settings_with_descriptor` in
   src/fonts/font_description.rs, from
   third_party/blink/renderer/platform/fonts/font_description.cc.

Copyright (C) 2006 Apple Computer, Inc.  All rights reserved.
Copyright (C) 2007 Nicholas Shanks <contact@nickshanks.com>
Copyright (C) 2008 Apple Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1.  Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
2.  Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
3.  Neither the name of Apple Computer, Inc. ("Apple") nor the names of
    its contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


8. `FontSelectionValue`, `FontSelectionRange`, `FontSelectionRequest`, and
   `FontSelectionCapabilities` in src/fonts/font_selection_types.rs, and
   `FontSelectionAlgorithm` in src/fonts/font_selection_algorithm.rs, from
   third_party/blink/renderer/platform/fonts/font_selection_types.h,
   third_party/blink/renderer/platform/fonts/font_selection_types.cc, and
   third_party/blink/renderer/platform/fonts/font_selection_algorithm.cc.

Copyright (C) 2017 Apple Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
THE POSSIBILITY OF SUCH DAMAGE.


9. The custom-property variable substitution in src/style/stylesheets_vars.rs,
   the computed custom-property inheritance in src/style/custom_properties.rs,
   and declaration staging in src/style/stylesheets.rs, adapted from
   third_party/blink/renderer/core/css/resolver/style_cascade.cc,
   third_party/blink/renderer/core/css/resolver/cascade_resolver.cc, and
   third_party/blink/renderer/core/css/parser/css_variable_parser.cc.
   src/style/stylesheets_tests.rs includes differential cases based on
   third_party/blink/renderer/core/css/resolver/style_cascade_test.cc.

Copyright 2015-2020 The Chromium Authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## 2. tiny-skia

The anti-aliasing takumi renders with (`.skia_ss` in `src/raster/rasterizer.zig`, edge setup in
`src/raster/skia_aa.zig`, the blend pipeline in `src/raster/blend.zig`, fake-bold stroking) reproduces
[tiny-skia](https://github.com/linebender/tiny-skia), a Rust port of Skia, itself under the Skia license.

```text
Copyright (c) 2011 Google Inc. All rights reserved.
Copyright (c) 2020 Yevhenii Reizner All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of the copyright holder nor the names of its
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## 3. HarfBuzz

The OpenType layout engine and shapers (`src/font/ot.zig`, `shape.zig`, `normalize.zig`,
`shaper_arabic.zig`, `shaper_indic.zig`, the Indic category tables in `indic_data.zig`) are modelled on
and partly ported from [HarfBuzz](https://github.com/harfbuzz/harfbuzz).

```text
HarfBuzz is licensed under the so-called "Old MIT" license.  Details follow.

Copyright © 2010-2022  Google, Inc.
Copyright © 2015-2020  Ebrahim Byagowi
Copyright © 2019,2020  Facebook, Inc.
Copyright © 2012,2015  Mozilla Foundation
Copyright © 2011  Codethink Limited
Copyright © 2008,2010  Nokia Corporation and/or its subsidiary(-ies)
Copyright © 2009  Keith Stribley
Copyright © 2011  Martin Hosken and SIL International
Copyright © 2007  Chris Wilson
Copyright © 2005,2006,2020,2021,2022,2023  Behdad Esfahbod
Copyright © 2004,2007,2008,2009,2010,2013,2021,2022,2023  Red Hat, Inc.
Copyright © 1998-2005  David Turner and Werner Lemberg
Copyright © 2016  Igalia S.L.
Copyright © 2022  Matthias Clasen
Copyright © 2018,2021  Khaled Hosny
Copyright © 2018,2019,2020  Adobe, Inc
Copyright © 2013-2015  Alexei Podtelezhnikov

For full copyright notices consult the individual files in the package.


Permission is hereby granted, without written agreement and without
license or royalty fees, to use, copy, modify, and distribute this
software and its documentation for any purpose, provided that the
above copyright notice and the following two paragraphs appear in
all copies of this software.

IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE TO ANY PARTY FOR
DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN
IF THE COPYRIGHT HOLDER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
DAMAGE.

THE COPYRIGHT HOLDER SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING,
BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
ON AN "AS IS" BASIS, AND THE COPYRIGHT HOLDER HAS NO OBLIGATION TO
PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
```

## 4. libwebp

The lossy WebP (VP8) decoder `src/codec/vp8.zig` is a bit-exact port of libwebp's decoder; the animated
WebP / GIF compositing in `src/codec/anim.zig` follows libwebp's `WebPAnimDecoder` / `anim_util`.

```text
Copyright (c) 2010, Google Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of Google nor the names of its contributors may
    be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

libwebp is also accompanied by Google's "Additional IP Rights Grant (Patents)" for the WebM project:
https://chromium.googlesource.com/webm/libwebp/+/refs/heads/main/PATENTS

## 5. Independent JPEG Group

The JPEG encoder and decoder (`src/codec/jpeg_enc.zig`, `src/codec/jpeg_dec.zig`) implement libjpeg's
"islow" integer DCTs (`jfdctint.c`, `jidctint.c`), the IJG quality scaling and "fancy" upsampling.

This software is based in part on the work of the Independent JPEG Group.

## 6. Unicode data and algorithms

The tables `src/font/ucd.zig`, `nfdata.zig`, `indic_data.zig` and `color_emoji_tables.zig` are generated
from the Unicode Character Database (16.0) and `emoji-data.txt` (17.0); bidi follows UAX #9 and ICU
(`adjustWSLevels` in `ubidi.cpp`, via takumi); line breaking follows UAX #14 as implemented by ICU4X.

```text
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.

SPDX-License-Identifier: Unicode-3.0
```

## 7. emoji-segmenter

The emoji presentation scanner in `src/font/color_emoji.zig` follows takumi's
`emoji_presentation_scanner.rs`, a hand-written form of the grammar in
[emoji-segmenter](https://github.com/google/emoji-segmenter)'s `emoji_presentation_scanner.rl`.

```text
Copyright 2019 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

The full Apache License 2.0 text is in `LICENSE-APACHE`.

## 8. Brotli

The WOFF2 decoder (`src/woff/brotli.zig`, compiled into the standard and full engines and into
`bm_woff.wasm`) embeds the 122,784-byte Brotli static dictionary and transform tables of RFC 7932 /
[google/brotli](https://github.com/google/brotli).

```text
Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## 9. Taffy

The flexbox algorithm (`src/layout/flex.zig`) and parts of the layout tree helpers are structured after
[Taffy](https://github.com/DioxusLabs/taffy), the layout library takumi uses.

```text
MIT License

Copyright (c) 2018 Visly Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## Acknowledgements (behaviour matched; no code or data taken)

- skrifa / FreeType: CFF and variable-font outline arithmetic is written to give identical results.
- zlib / miniz: DEFLATE encoder heuristics (lazy matching, `TOO_FAR`, Huffman length limiting).
- jpeg-encoder (the Rust crate takumi uses): two-pass optimised Huffman tables.
- HTML named character references (WHATWG), via takumi's table in `src/html/entity_data.zig`.
