from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, PageBreak

ROOT = Path('/Users/albinosiby/Tatos Dev/booking')
OUT = ROOT / 'output/pdf/booking-os-child-safety-standards-draft.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
FONT_ROOT = Path('/Users/albinosiby/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype')
pdfmetrics.registerFont(TTFont('SafetyBody', str(FONT_ROOT / 'LiberationSans-Regular.ttf')))
pdfmetrics.registerFont(TTFont('SafetyBold', str(FONT_ROOT / 'LiberationSans-Bold.ttf')))
pdfmetrics.registerFontFamily('SafetyBody', normal='SafetyBody', bold='SafetyBold', italic='SafetyBody', boldItalic='SafetyBold')
INK = colors.HexColor('#142018')
GREEN = colors.HexColor('#337418')
MUTED = colors.HexColor('#5C6860')
STYLES = {
    'title': ParagraphStyle('title', fontName='SafetyBold', fontSize=28, leading=31, textColor=INK, spaceAfter=11),
    'meta': ParagraphStyle('meta', fontName='SafetyBody', fontSize=10, leading=14, textColor=MUTED, spaceAfter=15),
    'h': ParagraphStyle('h', fontName='SafetyBold', fontSize=12, leading=16, textColor=GREEN, spaceBefore=9, spaceAfter=6, keepWithNext=True),
    'body': ParagraphStyle('body', fontName='SafetyBody', fontSize=10.4, leading=14.2, textColor=INK, spaceAfter=8),
    'note': ParagraphStyle('note', fontName='SafetyBody', fontSize=9.2, leading=12.6, textColor=MUTED, backColor=colors.HexColor('#F0F5EC'), borderPadding=9, spaceBefore=3, spaceAfter=13),
    'source': ParagraphStyle('source', fontName='SafetyBody', fontSize=8.6, leading=11.7, textColor=MUTED, spaceBefore=6),
}
story = []
def p(text, style='body'):
    story.append(Paragraph(text, STYLES[style]))
def h(text):
    p(text, 'h')

p('Child Safety Standards', 'title')
p('<b>Booking OS by Tatos Technology</b><br/>Standards against child sexual abuse and exploitation (CSAE)<br/>Review draft | 3 November 2026', 'meta')
p('<b>Draft status.</b> These are proposed standards for adoption by Tatos Technology. A designated child-safety contact, public reporting channel and operational response procedure must be confirmed before publication. This document does not certify that those arrangements are already in place.', 'note')
h('1. Purpose and scope')
p('Booking OS must not be used to abuse, exploit or endanger a child. For these standards, a child is anyone under 18. The standards apply to all users and organizations, including owners, staff and coaches, and to content and activity associated with Booking OS, its booking websites, uploads, support messages and connected services.')
p('Booking OS is a venue and business management service. Its business purpose does not reduce the obligation to protect children, including children whose coaching, attendance or booking records are managed by an organization.')
h('2. Prohibited content and conduct')
p('Tatos Technology prohibits child sexual abuse and exploitation (CSAE) and child sexual abuse material (CSAM). This includes creating, uploading, storing, requesting, distributing, promoting or linking to sexual abuse material involving a child, including digitally generated or manipulated material.')
p('Prohibited conduct also includes grooming; sexual solicitation of a child; coercion, threats or sexual extortion involving a child; trafficking or facilitating sexual exploitation; and using customer, booking, attendance or staff information to identify, contact or target a child for abuse. Users must not facilitate these activities or evade safety enforcement.')
h('3. Reporting a concern')
p('<b>Current in-app reporting route:</b> Profile &gt; Help &amp; support. Select <b>Other</b>, use the title <b>Child safety concern</b>, and describe the concern in text. Include relevant account, organization, booking or content identifiers and approximate dates where known.')
p('<b>Do not upload, download, copy or forward suspected CSAM to make a report.</b> Describe where it was encountered instead. Do not investigate, confront a suspected offender or circulate identifying information about a child. If a child faces immediate danger, contact local emergency services or law enforcement directly.')
p('Support tickets can be visible to authorized members of the reporting organization as well as platform support. This route is not an anonymous or confidential safeguarding channel. Do not include sensitive evidence or unnecessary details about a child. A separate public reporting channel must be confirmed before these standards are finalized.')

story.append(PageBreak())
h('4. Response and enforcement')
p('Under these standards, Tatos Technology will assess reports and known violations promptly, prioritize immediate risks to children, and restrict access to suspected harmful content or accounts while reviewing a concern where appropriate. On obtaining actual knowledge of CSAM on the service, it will take appropriate action, including removing or disabling access, consistently with applicable law and evidence-preservation requirements.')
p('Confirmed violations may lead to content removal, suspension or termination of account or organization access, and steps to prevent repeat abuse. Safety action may be taken without advance notice when notice could endanger a child, compromise evidence or interfere with an investigation. This draft makes no claim of continuous monitoring or guaranteed detection.')
h('5. Legal reporting and cooperation')
p('Tatos Technology will comply with applicable child-safety laws, including legally required reporting of confirmed CSAM or exploitation to the appropriate national or regional authority. It will cooperate with valid legal requests and preserve relevant records only as authorized or required by law. The appropriate reporting authority and procedure must be established for the jurisdictions in which the service operates.')
h('6. Privacy and handling of reports')
p('Reports should contain only information necessary to identify and assess the concern. Access to sensitive report material must be restricted to authorized personnel who need it for safeguarding, investigation or legal compliance. Information may be shared with competent authorities or relevant service providers when necessary and legally permitted; confidentiality cannot be guaranteed.')
p('Organizations must limit access to children\'s personal information to authorized personnel with a legitimate business need. They must not use booking, coaching, attendance or contact records to facilitate prohibited conduct. A secure evidence-handling process and a retention schedule for safeguarding records must be confirmed before publication.')
h('7. Child-safety responsibility and contact')
p('<b>Responsible developer:</b> Tatos Technology.<br/><b>Service:</b> Booking OS.<br/><b>Current general reporting route:</b> Profile &gt; Help &amp; support.')
p('Before adopting these standards, Tatos Technology must designate a person able to address CSAE and CSAM prevention practices and provide that person\'s contact information in Play Console where required. It must also confirm a monitored public reporting method for people who cannot access the app. No individual, email address or response deadline has been supplied for this draft.')
h('8. Publication and review')
p('The adopted standards should state their effective date and be published at a working, publicly accessible URL that identifies Booking OS or Tatos Technology. Review them when service features, legal duties or reporting arrangements change, and communicate material updates through an appropriate service channel.')
p('<b>To finalize:</b> approve these standards; appoint the child-safety contact; confirm the public reporting channel, escalation and lawful reporting process; establish restricted evidence handling and retention; then publish the approved version. Retain this copy as a draft until those steps are complete.', 'note')
p('Reference: <link href="https://support.google.com/googleplay/android-developer/answer/14747720?hl=en" color="#337418">Google Play - Child Safety Standards policy guidance</link>. Reviewed 3 November 2026. Publish your own approved standards URL.', 'source')

def decorate(c, doc):
    c.saveState()
    w, height = A4
    c.setFillColor(GREEN)
    c.rect(48, height-38, 28, 4, stroke=0, fill=1)
    c.setFont('SafetyBold', 8)
    c.setFillColor(MUTED)
    c.drawRightString(w-48, height-36, 'BOOKING OS / CHILD SAFETY')
    c.setStrokeColor(colors.HexColor('#DCE3D8'))
    c.line(48, 43, w-48, 43)
    c.setFont('SafetyBody', 8)
    c.drawString(48, 29, 'Tatos Technology | Review draft | 3 November 2026')
    c.drawRightString(w-48, 29, f'{doc.page} / 2')
    c.restoreState()

doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=48, rightMargin=48,
    topMargin=56, bottomMargin=59, title='Booking OS Child Safety Standards - Review Draft',
    author='Tatos Technology', subject='Proposed standards against child sexual abuse and exploitation')
doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
print(OUT)
