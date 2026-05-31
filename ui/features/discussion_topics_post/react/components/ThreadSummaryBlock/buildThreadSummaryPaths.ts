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

declare const ENV: {
  context_type?: string
  context_id?: string | number
  discussion_topic_id?: string | number
}

function threadSummaryBasePath(): string {
  const contextType = (ENV.context_type || 'Course').toLowerCase()
  const contextId = ENV.context_id
  const topicId = ENV.discussion_topic_id
  return `/api/v1/${contextType}s/${contextId}/discussion_topics/${topicId}/thread_summary`
}

export function buildThreadSummaryPath(locale: string): string {
  return `${threadSummaryBasePath()}?locale=${encodeURIComponent(locale)}`
}

export function buildThreadSummaryRegeneratePath(): string {
  return `${threadSummaryBasePath()}/regenerate`
}
