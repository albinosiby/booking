from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.pdfgen import canvas
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, KeepTogether
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT = Path('/Users/albinosiby/Tatos Dev/booking')
OUT = ROOT / 'output/pdf/booking-os-privacy-policy-draft.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
FONTS = Path('/Users/albinosiby/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype')
for name, filename in [('Body', 'LiberationSans-Regular.ttf'), ('Bold', 'LiberationSans-Bold.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(FONTS / filename)))
pdfmetrics.registerFontFamily('Body', normal='Body', bold='Bold', italic='Body', boldItalic='Bold')

INK = colors.HexColor('#161D1A')
GREEN = colors.HexColor('#337418')
MUTED = colors.HexColor('#5D6861')
styles = {
    'title': ParagraphStyle('title', fontName='Bold', fontSize=31, leading=34, textColor=INK, spaceAfter=10),
    'sub': ParagraphStyle('sub', fontName='Body', fontSize=10, leading=14, textColor=MUTED, spaceAfter=14),
    'h': ParagraphStyle('h', fontName='Bold', fontSize=12.2, leading=16, textColor=GREEN, spaceBefore=12, spaceAfter=6, keepWithNext=True),
    'body': ParagraphStyle('body', fontName='Body', fontSize=10.25, leading=14.5, textColor=INK, spaceAfter=8),
    'note': ParagraphStyle('note', fontName='Body', fontSize=9.2, leading=13, textColor=MUTED, backColor=colors.HexColor('#F0F5EC'), borderPadding=10, spaceBefore=6, spaceAfter=15),
}
story = []
def p(text, kind='body'):
    story.append(Paragraph(text, styles[kind]))
def heading(text): p(text, 'h')
def page(): story.append(PageBreak())

p('Privacy Policy', 'title')
p('<b>Booking OS by Tatos Technology</b> | Android app: bookingservice.tatos.tech<br/>Review draft dated 30 October 2026', 'sub')
p('<b>Publication review required.</b> Confirm the public privacy contact, retention schedule, enabled service providers and account-deletion process before publishing this policy. This draft does not establish an effective date.', 'note')
heading('1. About this policy')
p('Booking OS is a business management service provided by Tatos Technology for venue owners, managers, staff and coaches. This policy explains how personal information is handled through the mobile app and connected booking websites, support services and optional phone-booking service. In this policy, "we" refers to Tatos Technology.')
p('A venue or organization using Booking OS decides what customer and staff information to enter and how to use it for its business. For questions about a particular venue booking, payment or attendance record, contact that organization. For questions about the platform, use the contact route in section 12.')
heading('2. Information we collect')
p('<b>Account and team details.</b> Name, email address, account identifier, authentication and session information, sign-in provider, staff invitations, organization membership, role and assigned permissions. If you sign in with Google, the authentication service receives the account information authorized during sign-in.')
p('<b>Business and customer records.</b> Organization name and phone number; venue addresses, timezone and currency; business settings; customer name, phone number and optional email; bookings, cancellations, rescheduling, participant counts, coaching or membership plans, attendance and related notes and history.')
p('<b>Financial information.</b> Booking prices, collections, refunds, balances, income, expenses, transaction references, payment methods, bank names and account numbers, and any UPI identifier or payment QR image supplied by the organization. Uploaded invoices or receipts may contain personal information.')
p('<b>Uploads and support.</b> Images and documents you select, such as logos, venue photographs, QR images and invoices, plus support subjects, messages, author details and correspondence. Avoid including unnecessary sensitive information in notes or support messages.')

page()
heading('2. Information we collect (continued)')
p('<b>Technical information.</b> Authentication and request identifiers, network and server access information such as IP addresses, operational error information, device platform, app installation identifiers and push-notification tokens. Hosting and authentication providers may process technical logs to operate and secure the service.')
p('<b>Optional call information.</b> When an organization enables phone bookings, caller number, name if provided, interaction identifier, call times, duration, outcome, booking actions, summaries and transcripts may be processed. Audio recordings may be available through the voice provider. See section 9.')
heading('3. How we use information')
p('We use information to create and authenticate accounts; administer organizations and staff access; manage availability, bookings, attendance and plans; maintain financial records and reports; deliver service emails and booking notifications; provide customer support; investigate errors and misuse; and meet applicable legal obligations.')
p('We use selected images and documents for the feature you request. A venue may publish its business information, photographs and configured payment details on its booking website. Customers submit their contact and booking details to the organization they book with.')
p('Information required for account creation or a booking must be provided to complete that action. Optional permissions and optional features can be declined, although the corresponding functionality may then be unavailable.')
heading('4. When information is shared')
p('<b>Within your organization.</b> Owners and authorized members can access information according to their roles and assigned business access. Authorized platform administrators may access information to provide support, maintain the service, investigate misuse or manage integrations.')
p('<b>Service providers.</b> The platform uses Supabase for authentication, database and related cloud services; Google for Google sign-in and Firebase Cloud Messaging where enabled; infrastructure providers for hosting and delivery; configured email providers for service messages; and Sarvam for an enabled voice service. These providers process information needed for their respective services. Provider use depends on the deployed configuration.')
p('<b>Sharing you initiate.</b> Exported reports, downloaded files and booking messages may be shared with recipients or other apps you select. Those recipients handle the information under their own practices.')
p('<b>Legal and business circumstances.</b> Information may be disclosed when necessary to comply with law or valid legal process, protect users and the service, prevent fraud, or complete a business transfer subject to appropriate privacy protections and required notice.')
p('The reviewed app contains no advertising SDK or advertising analytics integration. This policy does not authorize selling personal information or using booking and account information for targeted advertising.')

page()
heading('5. Device permissions and local storage')
p('<b>Notifications.</b> If enabled, push notifications use an installation identifier and notification token. A booking alert may display a customer name, space, booking time and reference, including on the lock screen depending on your device settings. You can disable notifications or hide previews in Android settings.')
p('<b>Files and images.</b> The app uses system selection tools to access images or documents you choose for an upload. Selecting a file can send its contents to the service. The reviewed Android manifest does not request location, contacts, SMS, microphone or phone call-log access. Optional telephone calls are processed by the phone-service provider separately from device microphone access.')
p('<b>Local data.</b> The app stores authentication sessions and selected business snapshots using secure device storage, and stores preferences and unfinished configuration drafts locally. Read snapshots are scoped to account and organization access and are cleared on sign-out or access changes. Unpublished setup drafts may remain on the device for later recovery. Uninstalling the app does not delete cloud records.')
heading('6. Security and international processing')
p('The service uses HTTPS for production network connections, authenticated APIs, organization-based authorization and restricted database access. Mobile sessions and sensitive local snapshots use operating-system secure storage. No security measure can eliminate every risk; protect your device, account credentials and exported reports.')
p('Cloud and integration providers may process information outside your country. Applicable locations depend on the organization\'s hosting and provider configuration. Where required, the operator must use appropriate safeguards for cross-border processing.')
heading('7. Retention and deletion')
p('Account and business records remain in the service while needed to provide the organization\'s account and requested services. Financial, booking, attendance, support and security records may need different retention periods for accounting, dispute resolution, fraud prevention or legal obligations. Exact periods and backup-expiry arrangements must be confirmed by the operator before publication.')
p('Turning off a business or the optional phone service does not itself erase historical records. Saved call metadata and transcripts remain until removed through the platform\'s retention or deletion process; provider recordings follow the applicable provider configuration. No automatic call-data expiry is promised in this draft.')
p('To request account or personal-data deletion, use the support route in section 12. State which account and records the request concerns. Identity and authority may need verification. Before publication, the operator must confirm how requests are fulfilled, what is deleted or anonymized, any specific retention exceptions and periods, and how backups and provider copies are handled. Staff removal, sign-out and business deactivation are not equivalent to deleting a user account.')

page()
heading('8. Your choices and privacy requests')
p('You can manage available business and profile information in the app, control device permissions in Android settings, and ask your organization to correct records it maintains about you. Depending on applicable law, you may also request access, correction, a copy of your information, restriction or objection to processing, withdrawal of consent where processing relies on consent, or deletion.')
p('Send platform privacy requests through section 12. Customer and staff requests about organization-controlled records should also be directed to that organization. We may need information reasonably necessary to verify identity and determine the appropriate organization. Do not send passwords, authentication codes or full bank details in a privacy request.')
heading('9. Optional phone-booking service')
p('When enabled by an organization, Sarvam processes telephone conversations to answer enquiries and perform approved booking actions. Relevant caller and booking information is exchanged with Booking OS; call metadata, summaries and transcripts can be stored and shown to the organization owner. Recordings may be retrieved from the provider where available.')
p('The organization must provide any required call recording or AI-processing notice and obtain consent where required before processing begins. Callers can contact venue staff through another available channel instead of using the automated phone service. Switching off booking actions does not necessarily stop incoming calls from being answered by the telephone provider.')
heading('10. Children and information about minors')
p('Booking OS is intended for business owners and authorized personnel. It is not designed as a child-directed consumer app. A venue may use it to manage a child\'s coaching or attendance record; the organization is responsible for providing appropriate notices, obtaining parent or guardian authorization where required, and collecting only necessary information. Contact the organization and platform support if you believe information about a child has been handled inappropriately.')
heading('11. Changes to this policy')
p('The published policy should show its effective date and be updated when data practices change. Material changes should be communicated through the app or another appropriate channel, with additional consent obtained where required. This review draft must be finalized against the release configuration before it is presented as an effective policy.')
heading('12. Contact and requests')
p('<b>Current in-app route:</b> Profile &gt; Help &amp; support. Select "Other" and use a title such as "Privacy request" or "Account deletion request". Include your registered email, organization name and a description of the request. Support messages are visible to members of your organization and platform support; avoid unnecessary confidential details.')
p('<b>Developer:</b> Tatos Technology. A verified public privacy email or external contact method must be added before publication so people without app access can reach us. Contact details must match the published service and Google Play listing.')

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.states = []
    def showPage(self):
        self.states.append(dict(self.__dict__))
        self._startPage()
    def save(self):
        total = len(self.states)
        for state in self.states:
            self.__dict__.update(state)
            self.setStrokeColor(colors.HexColor('#DCE3D8'))
            self.line(48, 43, A4[0]-48, 43)
            self.setFillColor(MUTED)
            self.setFont('Body', 8)
            self.drawString(48, 29, 'Booking OS | Privacy Policy | Review draft')
            self.drawRightString(A4[0]-48, 29, f'{self._pageNumber} / {total}')
            super().showPage()
        super().save()

def decorate(c, doc):
    c.saveState()
    c.setFillColor(GREEN)
    c.rect(48, A4[1]-38, 28, 4, fill=True, stroke=False)
    c.setFont('Bold', 8)
    c.setFillColor(MUTED)
    c.drawRightString(A4[0]-48, A4[1]-36, 'BOOKING OS / PRIVACY')
    c.restoreState()

doc = SimpleDocTemplate(str(OUT), pagesize=A4, rightMargin=48, leftMargin=48,
    topMargin=56, bottomMargin=60, title='Booking OS Privacy Policy - Review Draft',
    author='Tatos Technology', subject='Privacy policy review draft for Google Play publication')
doc.build(story, onFirstPage=decorate, onLaterPages=decorate, canvasmaker=NumberedCanvas)
print(OUT)
