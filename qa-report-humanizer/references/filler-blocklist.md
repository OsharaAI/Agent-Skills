# Filler-phrase blocklist

A ready-to-use list of AI-tell phrases that a QA-report rewrite must not still contain.
`SKILL.md`'s Verification section greps against this list directly — if any entry below
turns up in the rewritten output, the rewrite hasn't done its job.

## Banned filler phrases

```
It is worth noting that
It's worth noting
Moving forward
In conclusion
Despite challenges
Despite several challenges
The team is committed to
The team is aligned
Stakeholders can feel confident
This underscores the importance
underscoring the need
demonstrating significant improvement
showcasing the team's commitment
continued vigilance
proactive testing
mitigate potential issues
potential impact
could potentially
high-risk areas
continuous improvement
enhanced test coverage
comprehensive regression testing
across multiple touchpoints
trend positively
high-quality release
strong collaboration
technical excellence
customer focus
```

## Grep-ready regex (case-insensitive)

The pattern to use for the Verification step: a single alternation built around the
most damaging tells.

```
it('?s)? worth noting|moving forward|in conclusion|despite (several )?challenges|the team is (committed|aligned)|stakeholders can feel confident|underscor(es|ing)|demonstrating significant|showcasing the team|continued vigilance|proactive testing|mitigate potential|potential(ly)? impact|high-risk areas|continuous improvement|enhanced test coverage|comprehensive regression|across multiple touchpoints|trend(s|ing)? positively|high-quality release|strong collaboration|technical excellence|customer focus
```

## Synonym-cycling tells (test-result rewording)

The giveaway verbs when one outcome gets restated four different ways. Give each
outcome exactly one verb.

```
passed successfully
completed without issues
returned positive results
executed as expected
```

## Passive-voice "who broke it" dodges

Passive phrasing that dodges naming what actually broke. Convert these to active voice
with a named subject.

```
an issue was identified
a defect was discovered
was discovered that impacts
a defect was identified
```
