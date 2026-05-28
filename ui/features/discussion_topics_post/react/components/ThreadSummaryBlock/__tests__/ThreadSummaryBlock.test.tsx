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

import React from 'react'
import {act, render, waitFor} from '@testing-library/react'
import fakeENV from '@canvas/test-utils/fakeENV'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {ThreadSummaryBlock} from '../ThreadSummaryBlock'
import type {ThreadSummaryData} from '../useThreadSummary'

const server = setupServer()

declare const ENV: {
  discussion_topic_id: string
  context_id: string
  context_type: string
  LOCALE: string
  discussion_thread_summarizer_enabled?: boolean
}

const sampleSummary = {
  themes: ['Main theme A'],
  viewpoints: ['Majority viewpoint'],
  open_questions: ['What are the next steps?'],
  scope_mode: 'default',
}

const threadSummaryPath =
  '/api/v1/courses/1234/discussion_topics/5678/thread_summary'

const setup = () => render(<ThreadSummaryBlock />)

describe('ThreadSummaryBlock', () => {
  beforeAll(() => server.listen())

  afterAll(() => server.close())

  beforeEach(() => {
    fakeENV.setup({
      discussion_topic_id: '5678',
      context_id: '1234',
      context_type: 'Course',
      LOCALE: 'en',
      discussion_thread_summarizer_enabled: true,
    })
    vi.clearAllMocks()
  })

  afterEach(() => {
    fakeENV.teardown()
    server.resetHandlers()
    vi.useRealTimers()
  })

  const mockThreadSummary = (body: ThreadSummaryData) => {
    server.use(http.get(threadSummaryPath, () => HttpResponse.json(body)))
  }

  it('does not render when the API returns disabled', async () => {
    mockThreadSummary({
      status: 'disabled',
      enabled: false,
      enqueued: false,
      summary: null,
      record_id: null,
    })

    const {queryByTestId} = setup()

    await waitFor(() => {
      expect(queryByTestId('thread-summary-block')).toBeNull()
    })
  })

  it('renders summary text when status is current', async () => {
    mockThreadSummary({
      status: 'current',
      enabled: true,
      enqueued: false,
      summary: sampleSummary,
      record_id: 1,
    })

    const {findByTestId} = setup()

    const text = await findByTestId('thread-summary-text')
    expect(text.textContent).toContain('Main theme A')
  })

  it('renders stale alert and summary text when status is stale', async () => {
    mockThreadSummary({
      status: 'stale',
      enabled: true,
      enqueued: true,
      summary: sampleSummary,
      record_id: 1,
    })

    const {findByTestId} = setup()

    expect(await findByTestId('thread-summary-stale-alert')).toBeInTheDocument()
    expect(await findByTestId('thread-summary-text')).toBeInTheDocument()
  })

  it('renders generating state with aria-live region', async () => {
    mockThreadSummary({
      status: 'generating',
      enabled: true,
      enqueued: true,
      summary: null,
      record_id: null,
    })

    const {findByTestId} = setup()

    const generating = await findByTestId('thread-summary-generating')
    expect(generating).toHaveAttribute('aria-live', 'polite')
  })

  it('polls again after 5 seconds while status is generating', async () => {
    vi.useFakeTimers({toFake: ['setInterval', 'clearInterval']})
    let requestCount = 0

    server.use(
      http.get(threadSummaryPath, () => {
        requestCount += 1
        if (requestCount === 1) {
          return HttpResponse.json({
            status: 'generating',
            enabled: true,
            enqueued: true,
            summary: null,
            record_id: null,
          })
        }
        return HttpResponse.json({
          status: 'current',
          enabled: true,
          enqueued: false,
          summary: sampleSummary,
          record_id: 1,
        })
      }),
    )

    const {findByTestId} = setup()

    await findByTestId('thread-summary-generating')

    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000)
    })

    await waitFor(() => {
      expect(requestCount).toBeGreaterThanOrEqual(2)
    })
    expect(await findByTestId('thread-summary-text')).toBeInTheDocument()
  })

  it('renders rate_limited_empty message without summary text', async () => {
    mockThreadSummary({
      status: 'rate_limited_empty',
      enabled: true,
      enqueued: false,
      summary: null,
      record_id: null,
    })

    const {findByTestId, queryByTestId} = setup()

    expect(await findByTestId('thread-summary-rate-limited-empty')).toBeInTheDocument()
    expect(queryByTestId('thread-summary-text')).toBeNull()
  })

  it('renders rate_limited_stale with summary and limit message', async () => {
    mockThreadSummary({
      status: 'rate_limited_stale',
      enabled: true,
      enqueued: false,
      summary: sampleSummary,
      record_id: 1,
    })

    const {findByTestId} = setup()

    expect(await findByTestId('thread-summary-text')).toBeInTheDocument()
    expect(await findByTestId('thread-summary-rate-limited-stale')).toBeInTheDocument()
  })
})
