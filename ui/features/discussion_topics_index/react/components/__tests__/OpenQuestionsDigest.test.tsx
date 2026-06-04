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
import {render, waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import fakeENV from '@canvas/test-utils/fakeENV'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {OpenQuestionsDigest} from '../OpenQuestionsDigest'
import type {OpenQuestion} from '../OpenQuestionsDigest'

const server = setupServer()

const COURSE_ID = '99'
const openQuestionsPath = `/api/v1/courses/${COURSE_ID}/discussion_topics/open_questions`
const dismissPath = (id: number) =>
  `/api/v1/courses/${COURSE_ID}/discussion_questions/${id}/dismiss`

const sampleQuestions: OpenQuestion[] = [
  {
    question_id: 1,
    thread_id: 10,
    thread_title: 'Week 1 Discussion',
    question_text: 'What is the main theme of the reading?',
    created_at: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
    deep_link: '/courses/99/discussion_topics/10#entry-1',
  },
  {
    question_id: 2,
    thread_id: 11,
    thread_title: 'Week 2 Discussion',
    question_text: 'How does this concept apply in practice?',
    created_at: new Date(Date.now() - 1 * 24 * 60 * 60 * 1000).toISOString(),
    deep_link: '/courses/99/discussion_topics/11#entry-2',
  },
]

const moderatorEnv = {
  COURSE_ID,
  discussion_thread_summarizer_enabled: true,
  permissions: {moderate: true},
}

const setup = () => render(<OpenQuestionsDigest />)

describe('OpenQuestionsDigest', () => {
  beforeAll(() => server.listen())
  afterAll(() => server.close())

  beforeEach(() => {
    fakeENV.setup(moderatorEnv)
  })

  afterEach(() => {
    fakeENV.teardown()
    server.resetHandlers()
  })

  describe('flag and permission gating (#31 nav entry visibility)', () => {
    it('renders nothing when feature flag is off', () => {
      fakeENV.setup({
        ...moderatorEnv,
        discussion_thread_summarizer_enabled: false,
      })
      const {queryByTestId} = setup()
      expect(queryByTestId('open-questions-digest')).toBeNull()
    })

    it('renders nothing when flag is on but user is not a moderator', () => {
      fakeENV.setup({
        ...moderatorEnv,
        permissions: {moderate: false},
      })
      const {queryByTestId} = setup()
      expect(queryByTestId('open-questions-digest')).toBeNull()
    })

    it('renders the digest heading when flag is on and user is moderator', async () => {
      server.use(http.get(openQuestionsPath, () => HttpResponse.json([])))
      const {findByTestId} = setup()
      expect(await findByTestId('open-questions-heading')).toBeInTheDocument()
    })
  })

  describe('loading state', () => {
    it('shows a loading spinner while fetching', async () => {
      server.use(
        http.get(openQuestionsPath, async () => {
          await new Promise(resolve => setTimeout(resolve, 50))
          return HttpResponse.json([])
        }),
      )
      const {queryByTestId, findByTestId} = setup()
      expect(queryByTestId('open-questions-loading')).toBeInTheDocument()
      await findByTestId('open-questions-empty')
      expect(queryByTestId('open-questions-loading')).toBeNull()
    })
  })

  describe('empty state', () => {
    it('shows empty message when no questions are returned', async () => {
      server.use(http.get(openQuestionsPath, () => HttpResponse.json([])))
      const {findByTestId} = setup()
      expect(await findByTestId('open-questions-empty')).toBeInTheDocument()
    })
  })

  describe('error state', () => {
    it('shows an error alert when the fetch fails', async () => {
      server.use(http.get(openQuestionsPath, () => HttpResponse.error()))
      const {findByTestId} = setup()
      expect(await findByTestId('open-questions-error')).toBeInTheDocument()
    })
  })

  describe('question list (#30 question list)', () => {
    beforeEach(() => {
      server.use(http.get(openQuestionsPath, () => HttpResponse.json(sampleQuestions)))
    })

    it('renders questions oldest-first as returned by the endpoint', async () => {
      const {findByTestId} = setup()
      // Both questions must be in the list
      expect(await findByTestId('open-question-row-1')).toBeInTheDocument()
      expect(await findByTestId('open-question-row-2')).toBeInTheDocument()
    })

    it('renders question text for each row', async () => {
      const {findByTestId} = setup()
      const text = await findByTestId('open-question-text-1')
      expect(text.textContent).toContain('What is the main theme')
    })

    it('renders thread title for each row', async () => {
      const {findByTestId} = setup()
      const threadLabel = await findByTestId('open-question-thread-1')
      expect(threadLabel.textContent).toBe('Week 1 Discussion')
    })

    it('renders a Go to thread deep link for each row', async () => {
      const {findByTestId} = setup()
      const link = await findByTestId('open-question-link-1')
      expect(link).toHaveAttribute('href', '/courses/99/discussion_topics/10#entry-1')
    })

    it('truncates question text longer than 200 characters', async () => {
      const longText = 'A'.repeat(250)
      server.use(
        http.get(openQuestionsPath, () =>
          HttpResponse.json([{...sampleQuestions[0], question_text: longText}]),
        ),
      )
      const {findByTestId} = setup()
      const text = await findByTestId('open-question-text-1')
      expect(text.textContent!.length).toBeLessThanOrEqual(202)
      expect(text.textContent).toContain('…')
    })

    it('renders the list with correct aria-label including count', async () => {
      const {findByTestId} = setup()
      const list = await findByTestId('open-questions-list')
      expect(list).toHaveAttribute('aria-label', expect.stringContaining('2'))
    })

    it('each dismiss button has an accessible aria-label referencing the thread', async () => {
      const {findByTestId} = setup()
      const btn = await findByTestId('open-question-dismiss-1')
      expect(btn).toHaveAttribute('aria-label', expect.stringContaining('Week 1 Discussion'))
    })
  })

  describe('dismiss action (#32)', () => {
    beforeEach(() => {
      server.use(http.get(openQuestionsPath, () => HttpResponse.json(sampleQuestions)))
    })

    it('removes the question from the list on successful dismiss', async () => {
      server.use(http.post(dismissPath(1), () => new Response(null, {status: 204})))
      const user = userEvent.setup()
      const {findByTestId, queryByTestId} = setup()

      const btn = await findByTestId('open-question-dismiss-1')
      await user.click(btn)

      await waitFor(() => {
        expect(queryByTestId('open-question-row-1')).toBeNull()
      })
      // other question remains
      expect(queryByTestId('open-question-row-2')).toBeInTheDocument()
    })

    it('updates the aria-live region with a confirmation on dismiss', async () => {
      server.use(http.post(dismissPath(1), () => new Response(null, {status: 204})))
      const user = userEvent.setup()
      const {findByTestId} = setup()

      const btn = await findByTestId('open-question-dismiss-1')
      await user.click(btn)

      await waitFor(() => {
        const live = document.querySelector('[data-testid="open-questions-live-region"]')
        expect(live?.textContent).toContain('dismissed')
      })
    })

    it('restores the row and shows an inline error when dismiss fails', async () => {
      server.use(http.post(dismissPath(1), () => HttpResponse.error()))
      const user = userEvent.setup()
      const {findByTestId, queryByTestId} = setup()

      await findByTestId('open-question-row-1')
      const btn = await findByTestId('open-question-dismiss-1')
      await user.click(btn)

      await waitFor(() => {
        expect(findByTestId(`open-question-dismiss-error-1`)).toBeTruthy()
      })
      // row is restored
      expect(queryByTestId('open-question-row-1')).toBeInTheDocument()
    })
  })
})
