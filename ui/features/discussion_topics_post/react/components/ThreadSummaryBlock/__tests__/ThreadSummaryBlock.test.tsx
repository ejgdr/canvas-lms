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
import userEvent from '@testing-library/user-event'
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

const threadSummaryPath = '/api/v1/courses/1234/discussion_topics/5678/thread_summary'

const threadSummaryRegeneratePath = `${threadSummaryPath}/regenerate`

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

  const mockRegenerate = (handler: () => ReturnType<typeof HttpResponse.json> | Response) => {
    server.use(http.post(threadSummaryRegeneratePath, handler))
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

  it('enqueues regeneration and shows generating state when regenerate succeeds', async () => {
    let regenerateCount = 0

    mockThreadSummary({
      status: 'current',
      enabled: true,
      enqueued: false,
      summary: sampleSummary,
      record_id: 1,
      regeneration: {available: true},
    })

    mockRegenerate(() => {
      regenerateCount += 1
      return HttpResponse.json({status: 'generating', enqueued: true})
    })

    server.use(
      http.get(threadSummaryPath, () => {
        if (regenerateCount > 0) {
          return HttpResponse.json({
            status: 'generating',
            enabled: true,
            enqueued: true,
            summary: null,
            record_id: 1,
            regeneration: {available: false, reason: 'cooldown', retry_after_seconds: 600},
          })
        }
        return HttpResponse.json({
          status: 'current',
          enabled: true,
          enqueued: false,
          summary: sampleSummary,
          record_id: 1,
          regeneration: {available: true},
        })
      }),
    )

    const user = userEvent.setup()
    const {findByTestId, queryByTestId} = setup()

    const button = await findByTestId('thread-summary-regenerate-button')
    await user.click(button)

    await waitFor(() => {
      expect(regenerateCount).toBe(1)
    })
    expect(await findByTestId('thread-summary-generating')).toBeInTheDocument()
    expect(queryByTestId('thread-summary-regenerate-button')).toBeNull()
  })

  it('shows cooldown feedback with aria-disabled and does not POST when in cooldown', async () => {
    let regenerateCount = 0

    mockThreadSummary({
      status: 'current',
      enabled: true,
      enqueued: false,
      summary: sampleSummary,
      record_id: 1,
      regeneration: {
        available: false,
        reason: 'cooldown',
        retry_after_seconds: 240,
      },
    })

    mockRegenerate(() => {
      regenerateCount += 1
      return HttpResponse.json({error: 'cooldown', retry_after_seconds: 240}, {status: 429})
    })

    const user = userEvent.setup()
    const {findByTestId} = setup()

    const button = await findByTestId('thread-summary-regenerate-button')
    expect(button).toHaveAttribute('aria-disabled', 'true')
    expect(button).not.toHaveAttribute('disabled')

    button.focus()
    expect(button).toHaveFocus()

    await user.click(button)

    expect(regenerateCount).toBe(0)
    expect(await findByTestId('thread-summary-regenerate-cooldown')).toBeInTheDocument()
  })

  it('renders disclosure when summary.disclosure is set and status is current', async () => {
    mockThreadSummary({
      status: 'current',
      enabled: true,
      enqueued: false,
      summary: {
        ...sampleSummary,
        disclosure: 'Based on instructor posts and your posts only',
      },
      record_id: 1,
    })

    const {findByTestId} = setup()

    const disclosure = await findByTestId('thread-summary-disclosure')
    expect(disclosure.textContent).toBe('Based on instructor posts and your posts only')
  })

  it('renders disclosure when summary.disclosure is set and status is stale', async () => {
    mockThreadSummary({
      status: 'stale',
      enabled: true,
      enqueued: true,
      summary: {
        ...sampleSummary,
        disclosure: 'Based on instructor posts and your posts only',
      },
      record_id: 1,
    })

    const {findByTestId} = setup()

    expect(await findByTestId('thread-summary-stale-alert')).toBeInTheDocument()
    const disclosure = await findByTestId('thread-summary-disclosure')
    expect(disclosure.textContent).toBe('Based on instructor posts and your posts only')
  })

  it('does not render disclosure element when summary.disclosure is null', async () => {
    mockThreadSummary({
      status: 'current',
      enabled: true,
      enqueued: false,
      summary: {...sampleSummary, disclosure: null},
      record_id: 1,
    })

    const {findByTestId, queryByTestId} = setup()

    await findByTestId('thread-summary-text')
    expect(queryByTestId('thread-summary-disclosure')).toBeNull()
  })

  it('shows the report button when status is current', async () => {
    mockThreadSummary({
      status: 'current',
      enabled: true,
      enqueued: false,
      summary: sampleSummary,
      record_id: 1,
    })

    const {findByTestId} = setup()

    expect(await findByTestId('thread-summary-report-button')).toBeInTheDocument()
  })

  it('shows the report button when status is stale', async () => {
    mockThreadSummary({
      status: 'stale',
      enabled: true,
      enqueued: true,
      summary: sampleSummary,
      record_id: 1,
    })

    const {findByTestId} = setup()

    expect(await findByTestId('thread-summary-report-button')).toBeInTheDocument()
  })

  it('does not show the report button when status is generating', async () => {
    mockThreadSummary({
      status: 'generating',
      enabled: true,
      enqueued: true,
      summary: null,
      record_id: null,
    })

    const {findByTestId, queryByTestId} = setup()

    await findByTestId('thread-summary-generating')
    expect(queryByTestId('thread-summary-report-button')).toBeNull()
  })

  it('does not show the report button when status is rate_limited_empty', async () => {
    mockThreadSummary({
      status: 'rate_limited_empty',
      enabled: true,
      enqueued: false,
      summary: null,
      record_id: null,
    })

    const {findByTestId, queryByTestId} = setup()

    await findByTestId('thread-summary-rate-limited-empty')
    expect(queryByTestId('thread-summary-report-button')).toBeNull()
  })

  it('shows inline quota-exhausted message instead of a toast', async () => {
    mockThreadSummary({
      status: 'current',
      enabled: true,
      enqueued: false,
      summary: sampleSummary,
      record_id: 1,
      regeneration: {available: true},
    })

    mockRegenerate(() =>
      HttpResponse.json(
        {
          error: 'quota_exhausted',
          message: 'Daily regeneration limit reached. Try again later.',
        },
        {status: 429},
      ),
    )

    const user = userEvent.setup()
    const {findByTestId, queryByTestId} = setup()

    await user.click(await findByTestId('thread-summary-regenerate-button'))

    expect(await findByTestId('thread-summary-quota-exhausted')).toBeInTheDocument()
    expect(queryByTestId('thread-summary-generating')).toBeNull()
  })
})
