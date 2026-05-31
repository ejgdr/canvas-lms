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

import {useScope as createI18nScope} from '@canvas/i18n'

const I18n = createI18nScope('discussion_topics_post')

type TranslateFn = typeof I18n.t

/**
 * Converts a cooldown-remaining value (seconds) into whole minutes for display.
 * Rounds up so partial minutes never understate the wait.
 */
export function minutesUntilAvailable(retryAfterSeconds: number): number {
  if (!Number.isFinite(retryAfterSeconds) || retryAfterSeconds <= 0) {
    return 1
  }
  return Math.max(1, Math.ceil(retryAfterSeconds / 60))
}

/**
 * Formats the regenerate-button cooldown label ("Available in X minutes").
 */
export function formatRegenerationCooldownLabel(
  retryAfterSeconds: number,
  t: TranslateFn = I18n.t.bind(I18n),
): string {
  const minutes = minutesUntilAvailable(retryAfterSeconds)
  return t(
    {one: 'Available in 1 minute', other: 'Available in %{count} minutes'},
    {count: minutes},
  )
}
