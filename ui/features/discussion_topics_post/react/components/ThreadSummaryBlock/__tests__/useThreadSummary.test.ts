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
  POLL_GENERATING_MS,
  POLL_STALE_MS,
  pollIntervalForStatus,
} from '../useThreadSummary'

describe('pollIntervalForStatus', () => {
  it('returns 5s for generating', () => {
    expect(pollIntervalForStatus('generating')).toBe(POLL_GENERATING_MS)
  })

  it('returns 30s for stale and rate_limited_stale', () => {
    expect(pollIntervalForStatus('stale')).toBe(POLL_STALE_MS)
    expect(pollIntervalForStatus('rate_limited_stale')).toBe(POLL_STALE_MS)
  })

  it('returns null for terminal or idle states', () => {
    expect(pollIntervalForStatus('current')).toBeNull()
    expect(pollIntervalForStatus('disabled')).toBeNull()
    expect(pollIntervalForStatus('rate_limited_empty')).toBeNull()
  })
})
