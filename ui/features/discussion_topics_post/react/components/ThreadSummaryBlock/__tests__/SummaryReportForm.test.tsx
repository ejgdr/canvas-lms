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
import {act, fireEvent, render, waitFor, within} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import fakeENV from '@canvas/test-utils/fakeENV'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {SummaryReportForm, REPORT_REASONS} from '../SummaryReportForm'

const server = setupServer()

const reportPath = '/api/v1/courses/1234/discussion_topics/5678/thread_summary/report'

const setup = () => render(<SummaryReportForm />)

describe('SummaryReportForm', () => {
  beforeAll(() => server.listen())

  afterAll(() => server.close())

  beforeEach(() => {
    fakeENV.setup({
      discussion_topic_id: '5678',
      context_id: '1234',
      context_type: 'Course',
    })
  })

  afterEach(() => {
    fakeENV.teardown()
    server.resetHandlers()
  })

  it('shows the Report summary button', () => {
    const {getByTestId} = setup()
    expect(getByTestId('thread-summary-report-button')).toBeInTheDocument()
  })

  it('opens the picker modal when the button is clicked', async () => {
    const user = userEvent.setup()
    const {getByTestId, findByRole} = setup()

    await user.click(getByTestId('thread-summary-report-button'))

    const modal = await findByRole('dialog')
    expect(modal).toBeInTheDocument()
  })

  it('renders exactly four reason options', async () => {
    const user = userEvent.setup()
    const {getByTestId, findByRole} = setup()

    await user.click(getByTestId('thread-summary-report-button'))

    const modal = await findByRole('dialog')
    const radios = within(modal).getAllByRole('radio')
    expect(radios).toHaveLength(4)
  })

  it('renders options mapping to the four backend enum values', async () => {
    const user = userEvent.setup()
    const {getByTestId, findByTestId} = setup()

    await user.click(getByTestId('thread-summary-report-button'))

    for (const r of REPORT_REASONS) {
      expect(await findByTestId(`thread-summary-report-reason-${r.value}`)).toBeInTheDocument()
    }
  })

  it('POSTs to the correct path with reason and comment on submit', async () => {
    let captured: {reason?: string; comment?: string} = {}

    server.use(
      http.post(reportPath, async ({request}) => {
        const body = (await request.json()) as {reason?: string; comment?: string}
        captured = body
        return HttpResponse.json({id: 1, reason: body.reason, reporter_role: 'student'}, {status: 201})
      }),
    )

    const user = userEvent.setup()
    const {getByTestId, findByTestId} = setup()

    await user.click(getByTestId('thread-summary-report-button'))

    const reasonInput = await findByTestId('thread-summary-report-reason-inaccurate')
    await user.click(reasonInput)

    const commentInput = await findByTestId('thread-summary-report-comment')
    await user.clear(commentInput)
    await user.type(commentInput, 'Test comment')

    await user.click(getByTestId('thread-summary-report-submit'))

    await waitFor(() => {
      expect(captured.reason).toBe('inaccurate')
      expect(captured.comment).toBe('Test comment')
    })
  })

  it('renders the confirmation message after a successful submission', async () => {
    server.use(
      http.post(reportPath, () =>
        HttpResponse.json({id: 1, reason: 'other', reporter_role: 'student'}, {status: 201}),
      ),
    )

    const user = userEvent.setup()
    const {getByTestId, findByTestId} = setup()

    await user.click(getByTestId('thread-summary-report-button'))
    await user.click(await findByTestId('thread-summary-report-reason-other'))
    await user.click(getByTestId('thread-summary-report-submit'))

    expect(await findByTestId('thread-summary-report-confirmation')).toBeInTheDocument()
  })

  it('closes the modal on Escape key', async () => {
    const user = userEvent.setup()
    const {getByTestId, findByRole, queryByRole} = setup()

    await user.click(getByTestId('thread-summary-report-button'))
    await findByRole('dialog')

    act(() => {
      // InstUI FocusRegion listens for keyup on document (with capture) to close on Escape
      fireEvent.keyUp(document, {key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true})
    })

    await waitFor(() => {
      expect(queryByRole('dialog')).toBeNull()
    })
  })

  it('disables submit and shows error when comment exceeds 500 characters', async () => {
    const user = userEvent.setup()
    const {getByTestId, findByTestId} = setup()

    await user.click(getByTestId('thread-summary-report-button'))
    await user.click(await findByTestId('thread-summary-report-reason-inaccurate'))

    const commentInput = await findByTestId('thread-summary-report-comment')
    const longComment = 'a'.repeat(501)
    await user.clear(commentInput)
    await user.type(commentInput, longComment)

    const submitButton = getByTestId('thread-summary-report-submit')
    expect(submitButton).toHaveAttribute('disabled')
  })
})
