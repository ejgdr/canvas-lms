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

import {
  formatRegenerationCooldownLabel,
  minutesUntilAvailable,
} from '../formatRegenerationCooldown'

describe('minutesUntilAvailable', () => {
  it('rounds up partial minutes', () => {
    expect(minutesUntilAvailable(61)).toBe(2)
    expect(minutesUntilAvailable(120)).toBe(2)
    expect(minutesUntilAvailable(121)).toBe(3)
  })

  it('returns at least one minute for non-positive values', () => {
    expect(minutesUntilAvailable(0)).toBe(1)
    expect(minutesUntilAvailable(-5)).toBe(1)
  })
})

describe('formatRegenerationCooldownLabel', () => {
  const t = vi.fn((key, options) => {
    if (typeof key === 'object' && options?.count === 1) {
      return 'Available in 1 minute'
    }
    return `Available in ${options?.count} minutes`
  })

  it('formats singular minute', () => {
    expect(formatRegenerationCooldownLabel(45, t)).toBe('Available in 1 minute')
  })

  it('formats plural minutes using rounded-up value', () => {
    expect(formatRegenerationCooldownLabel(130, t)).toBe('Available in 3 minutes')
  })
})
