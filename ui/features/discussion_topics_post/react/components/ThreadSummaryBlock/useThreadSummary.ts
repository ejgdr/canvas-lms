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

/**
 * Hook for fetching and polling the thread summary endpoint.
 *
 * Polling intervals: 5s for :generating, 30s for :stale and :rate_limited_stale.
 * No polling for :current, :disabled, :rate_limited_empty.
 *
 * Locale handling: enqueue_for singleton key on the backend is topic-id only
 * (Cycle 19 finding). Multi-locale render requests collapse to one job. On
 * locale change, this hook refetches — the server may still serve a summary
 * generated for another locale until the next regeneration cycle.
 *
 * Cleanup: AbortController cancels in-flight fetches; clearInterval stops
 * polling. Both fire on unmount AND on dependency changes.
 */

import {useCallback, useEffect, useState} from 'react'
import doFetchApi from '@canvas/do-fetch-api-effect'
import type {ThreadSummaryPayload} from './formatThreadSummary'

export type ThreadSummaryStatus =
  | 'current'
  | 'stale'
  | 'generating'
  | 'rate_limited_stale'
  | 'rate_limited_empty'
  | 'disabled'

export interface ThreadSummaryData {
  status: ThreadSummaryStatus
  enabled: boolean
  enqueued: boolean
  summary: ThreadSummaryPayload | null
  record_id: number | null
}

export const POLL_GENERATING_MS = 5000
export const POLL_STALE_MS = 30000

declare const ENV: {
  context_type?: string
  context_id?: string | number
  discussion_topic_id?: string | number
  LOCALE?: string
}

export function pollIntervalForStatus(status: ThreadSummaryStatus | null | undefined): number | null {
  if (!status) {
    return null
  }
  if (status === 'generating') {
    return POLL_GENERATING_MS
  }
  if (status === 'stale' || status === 'rate_limited_stale') {
    return POLL_STALE_MS
  }
  return null
}

function buildThreadSummaryPath(locale: string): string {
  const contextType = (ENV.context_type || 'Course').toLowerCase()
  const contextId = ENV.context_id
  const topicId = ENV.discussion_topic_id
  return `/api/v1/${contextType}s/${contextId}/discussion_topics/${topicId}/thread_summary?locale=${encodeURIComponent(locale)}`
}

export function useThreadSummary() {
  const locale = ENV.LOCALE || 'en'
  const [data, setData] = useState<ThreadSummaryData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchSummary = useCallback(
    async (signal: AbortSignal) => {
      const {json} = await doFetchApi<ThreadSummaryData>({
        path: buildThreadSummaryPath(locale),
        method: 'GET',
        signal,
      })
      if (signal.aborted) {
        return null
      }
      return json ?? null
    },
    [locale],
  )

  useEffect(() => {
    const controller = new AbortController()
    let intervalId: ReturnType<typeof setInterval> | undefined

    const clearPoll = () => {
      if (intervalId !== undefined) {
        clearInterval(intervalId)
        intervalId = undefined
      }
    }

    const load = async () => {
      try {
        const result = await fetchSummary(controller.signal)
        if (controller.signal.aborted) {
          return
        }
        setData(result)
        setError(null)
        clearPoll()
        const intervalMs = pollIntervalForStatus(result?.status)
        if (intervalMs != null) {
          intervalId = setInterval(() => {
            void load()
          }, intervalMs)
        }
      } catch (err) {
        if (controller.signal.aborted) {
          return
        }
        setError(err instanceof Error ? err : new Error(String(err)))
      } finally {
        if (!controller.signal.aborted) {
          setLoading(false)
        }
      }
    }

    setLoading(true)
    void load()

    return () => {
      controller.abort()
      clearPoll()
    }
  }, [fetchSummary, locale])

  return {data, loading, error}
}
