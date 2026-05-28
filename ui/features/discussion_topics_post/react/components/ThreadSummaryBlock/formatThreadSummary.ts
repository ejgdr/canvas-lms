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

export interface ThreadSummaryPayload {
  themes?: string[]
  viewpoints?: string[]
  open_questions?: string[]
  scope_mode?: string
}

/**
 * Formats the thread_summary JSON payload into display text for the UI.
 */
export function formatThreadSummary(summary: ThreadSummaryPayload | null | undefined): string {
  if (!summary || typeof summary !== 'object') {
    return ''
  }

  const sections: string[] = []

  if (Array.isArray(summary.themes) && summary.themes.length > 0) {
    sections.push(summary.themes.map(theme => `• ${theme}`).join('\n'))
  }

  if (Array.isArray(summary.viewpoints) && summary.viewpoints.length > 0) {
    sections.push(summary.viewpoints.map(viewpoint => `• ${viewpoint}`).join('\n'))
  }

  if (Array.isArray(summary.open_questions) && summary.open_questions.length > 0) {
    sections.push(summary.open_questions.map(question => `• ${question}`).join('\n'))
  }

  return sections.join('\n\n').trim()
}
