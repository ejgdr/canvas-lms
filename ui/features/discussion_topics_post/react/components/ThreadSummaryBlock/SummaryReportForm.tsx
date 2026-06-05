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

import React, {useState, useCallback} from 'react'
import {useScope as createI18nScope} from '@canvas/i18n'
import {Alert} from '@instructure/ui-alerts'
import {Button, CloseButton} from '@instructure/ui-buttons'
import {Flex} from '@instructure/ui-flex'
import {Heading} from '@instructure/ui-heading'
import {Modal} from '@instructure/ui-modal'
import {RadioInput, RadioInputGroup} from '@instructure/ui-radio-input'
import {Text} from '@instructure/ui-text'
import {TextArea} from '@instructure/ui-text-area'
import {View} from '@instructure/ui-view'
import doFetchApi from '@canvas/do-fetch-api-effect'
import {buildThreadSummaryReportPath} from './buildThreadSummaryPaths'

const I18n = createI18nScope('discussion_topics_post')

const COMMENT_MAX_LENGTH = 500

export const REPORT_REASONS = [
  {value: 'inaccurate', label: () => I18n.t('Inaccurate')},
  {value: 'missed_viewpoint', label: () => I18n.t('Missed a viewpoint')},
  {value: 'harmful_content', label: () => I18n.t('Harmful content')},
  {value: 'other', label: () => I18n.t('Other')},
] as const

type ReportReason = (typeof REPORT_REASONS)[number]['value']

export const SummaryReportForm = () => {
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState<ReportReason | ''>('')
  const [comment, setComment] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)

  const commentTooLong = comment.length > COMMENT_MAX_LENGTH

  const handleOpen = useCallback(() => {
    setOpen(true)
    setReason('')
    setComment('')
    setSubmitError(null)
  }, [])

  const handleClose = useCallback(() => {
    setOpen(false)
  }, [])

  const handleReasonChange = useCallback((_e: React.ChangeEvent<HTMLInputElement>, val: string) => {
    setReason(val as ReportReason)
  }, [])

  const handleCommentChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setComment(e.target.value)
  }, [])

  const handleSubmit = useCallback(async () => {
    if (!reason || commentTooLong || submitting) return

    setSubmitting(true)
    setSubmitError(null)

    try {
      await doFetchApi({
        path: buildThreadSummaryReportPath(),
        method: 'POST',
        body: {
          reason,
          ...(comment ? {comment} : {}),
        },
      })
      setOpen(false)
      setSubmitted(true)
    } catch {
      setSubmitError(I18n.t('Unable to submit report. Please try again.'))
    } finally {
      setSubmitting(false)
    }
  }, [reason, comment, commentTooLong, submitting])

  const commentMessages = commentTooLong
    ? [
        {
          type: 'error' as const,
          text: I18n.t('Comment must be %{max} characters or fewer.', {max: COMMENT_MAX_LENGTH}),
        },
      ]
    : []

  return (
    <>
      <Button
        color="secondary"
        size="small"
        data-testid="thread-summary-report-button"
        onClick={handleOpen}
      >
        {I18n.t('Report summary')}
      </Button>

      <div aria-live="polite" aria-atomic="true">
        {submitted && (
          <View as="div" margin="x-small 0 0 0">
            <Text size="small" data-testid="thread-summary-report-confirmation">
              {I18n.t('Report submitted. Thank you.')}
            </Text>
          </View>
        )}
      </div>

      <Modal
        open={open}
        onDismiss={handleClose}
        size="medium"
        label={I18n.t('Report summary')}
        shouldCloseOnDocumentClick={false}
        data-testid="thread-summary-report-modal"
      >
        <Modal.Header>
          <CloseButton
            placement="end"
            offset="small"
            onClick={handleClose}
            screenReaderLabel={I18n.t('Close')}
          />
          <Heading>{I18n.t('Report summary')}</Heading>
        </Modal.Header>
        <Modal.Body>
          {submitError && (
            <Alert variant="error" hasShadow={false} margin="0 0 small 0" data-testid="thread-summary-report-error">
              {submitError}
            </Alert>
          )}
          <RadioInputGroup
            name="thread-summary-report-reason"
            description={I18n.t('Why are you reporting this summary?')}
            value={reason}
            onChange={handleReasonChange}
          >
            {REPORT_REASONS.map(r => (
              <RadioInput
                key={r.value}
                value={r.value}
                label={r.label()}
                data-testid={`thread-summary-report-reason-${r.value}`}
              />
            ))}
          </RadioInputGroup>
          <View as="div" margin="medium 0 0 0">
            <TextArea
              label={I18n.t('Additional comments (optional, max %{max} characters)', {max: COMMENT_MAX_LENGTH})}
              value={comment}
              onChange={handleCommentChange}
              messages={commentMessages}
              data-testid="thread-summary-report-comment"
            />
          </View>
        </Modal.Body>
        <Modal.Footer>
          <Flex gap="small">
            <Flex.Item>
              <Button
                onClick={handleClose}
                data-testid="thread-summary-report-cancel"
              >
                {I18n.t('Cancel')}
              </Button>
            </Flex.Item>
            <Flex.Item>
              <Button
                color="primary"
                onClick={() => void handleSubmit()}
                interaction={!reason || commentTooLong || submitting ? 'disabled' : 'enabled'}
                data-testid="thread-summary-report-submit"
              >
                {I18n.t('Submit report')}
              </Button>
            </Flex.Item>
          </Flex>
        </Modal.Footer>
      </Modal>
    </>
  )
}
