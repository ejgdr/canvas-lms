/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import {formatThreadSummary} from '../formatThreadSummary'

describe('formatThreadSummary', () => {
  it('formats themes, viewpoints, and open questions', () => {
    const text = formatThreadSummary({
      themes: ['Theme A'],
      viewpoints: ['View B'],
      open_questions: ['Question C?'],
    })

    expect(text).toContain('• Theme A')
    expect(text).toContain('• View B')
    expect(text).toContain('• Question C?')
  })

  it('returns empty string for null summary', () => {
    expect(formatThreadSummary(null)).toBe('')
  })
})
