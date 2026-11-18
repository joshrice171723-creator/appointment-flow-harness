# Decisions

---

## PMS-related decisions

Chose not to change anything on the PMS if you acquired a new clinic, you can't change their software, especially if it's online SaaS so I wanted to maintain that constraint for this project.

Looking at the supplied DB, I can quickly see a couple of things that should be handled.

1. **Wireless phone free text:** That's a red flag, I made sure the seed data would put a lot of junk here for testing this should be handled.

2. **Only message adults:** If they are  under 18 direct the message to the responsible party. A 10 yr old might be afraid of the dentist and won't remind the parent lol and for other obvious reasons. If the birthdate is null we don't know if it's a child or an adult so don't send anything, make a task for the front desk to fix the birthdate instead.

   I also check that the responsible party is an adult and authorized in this system. A guarantor_id by itself isn't enough.

3. **Preferred language is often null:** default to English also handle Spanish I could have done more but chose just 2 to demonstrate I see the issue there.

4. **Patient naming convetion:** Names are just Demo Patient for all and I used the ID along with it this decision is simply for easier reviewing by you guys I figured a bunch of random names might be more annoying to follow while hopping around.

---

## Clarity

Page 5 of the take-home assessment asks for clarity.

> Clarity. Someone on our team could pick up your code and your notes next month and keep going.

That someone might be me a few months from now, and you should always be kind to your future self.

This exercise brought me back to a part of development I’ve always cared about: the craft of writing code that someone else can pick up, follow, and enjoy working with. I didn't want to have to memorize 1000s of lines of code to defend my work live in front of y'all. Proper code should be easily readable and changeable where if you just picked it up for the first time you can understand it with minimal effort.

After some time away from coding, I stepped back in and leaned heavily into AI. Lately, I’ve been focused on building AI systems, making them more capable, and testing how far I could push them. I spent a lot of time on the product and user experience, without slowing down enough to read the code underneath. This assignment exposed that blind spot in my workflow and AI harness.

I went through the code myself because it's downright disrespectful to send this off and expect y'all to read it if I hadn't; plus, I need to be able to defend it. It worked, but it was the worst thing ever to read; it wasn't clean, not to my standards. My first approach was to ask for specific improvements. I decided the first approach wasn't good enough and time-consuming, so I had AI help me build a rubric for human readability, guided by people in the industry I respect, such as Sandi Metz. Back at WeInfuse, I used to quote a few of Sandi Metz’s programming mantras.

### The Solution:

1. A rubric for reviewing code readability.
2. Coding guidelines informed by the books.

---

## User facing Design choices

My design principle is "Know at a glance, and understand in a click."

The assignment identifies three audiences: patients, front-desk staff, and operations leadership. I gave each a separate entrance so the reviewer can experience the workflow from each person's perspective.

For front-desk staff, I organized the experience around three places:

1. **Active work:** What needs attention now. This is a work queue, rather than a list staff must interpret to figure out their next action. It shows the amount of work and why each item needs attention. Claiming an item moves it to In progress so teammates can see who owns it and avoid duplicate calls.

2. **Resolved:** What has already been handled, including the outcome and who resolved it.

3. **Appointments:** A date-based view of the schedule, patient replies, confirmation status, and the outcome recorded in the PMS.

I kept the cards brief so staff can scan the queue quickly. Clicking a card reveals the conversation, appointment details, and activity history needed to act. The goal is to make the next action obvious while keeping its supporting information close by.

---

## Keeping the scope in proportion

I used AI to explore a bigger version first, then cut it back for the take-home. Y’all asked for proportion, so I went through what I’d built and asked what each person actually needed to do.

1. **Front desk.** I cut a good amount here, including time tracking. I left more detail on the front desk because more people would use it throughout the day. If a patient replies NO, staff need to see why it’s in the queue, read the reply, and know whether someone else is already handling it. That’s why I kept the work queue, case ownership, and follow-up history.

2. **Leadership.** I removed communication cost reporting and on-time arrival metrics. I kept the clinic comparison and the appointment outcomes we could actually show. If the page feels sparse, that was deliberate. I wanted someone to get the big picture quickly.

3. **Patients.** I removed the portal I’d built for email reminders. It added another place for the patient to go when a reply could do the job. I kept replies simple and gave the front desk a way to handle anything that needed a person.

4. **The person reviewing this.** I wanted y’all to be able to follow a reminder, a patient reply, and the front-desk follow-up without working through a bunch of extra screens. That also gave me a smaller codebase I could explain and defend. I removed the demo clock, feature-pilot/settings controls, and Demo Tools section.

---

## Other decisions

1. Chose not to send an email if they have already responded. reason $

2. Even if they confirmed on day 7, I still sent a courtesy message as a reminder it's a separate message than the confirmation.

3. I kept the interactive demo to two clinics so the reviewer would not have to work through a large list. However in test I benchmark 60 locations with 4000 appointments a day over 14 operating days, 56000 appointments total. The benchmark checks a 4000-message batch and that running it again does not send duplicates. The sender is simulated, so this measures the application and database work, not real vendor delivery.

---

## Assumptions

1. **status TEXT:** There is no canceled but based on "Sometimes staff break the old appointment and create a new one instead." It leads me to believe 'unscheduled' represents canceled and Broken represents rescheduled under a different appointment.

2. "You may add your own tables, schemas, or databases": I made it clearly separated by using two separate DBs. I kept the exact one you provided and worked off that I wanted to keep any intended difficulty or gotchas in place like the real world would have.

3. The demo assumes clinics are staffed Monday through Saturday.

4. Permission is granted to message the patient until revoked.

---

## When the messages go out

1. The messages go out at 10 AM in the clinic's own time zone, with same-day catch-up before 6 PM. If a whole day gets missed, it can catch up at the next daily run before the appointment starts. If more than one step is due, I combine them into one message instead of sending a pile of missed reminders. That can mean sending the day-before reminder on the appointment day if it has not started yet. I would rather send one useful reminder late than skip it because the system was down.

2. **7 days before:** send the first request by text. If text can't be used, use email instead.

3. **6 days before:** if nobody answered the text, send an email. If they already responded, no email.

4. **3 days before:** if still no answer and not confirmed, send another request.

5. **1 day before:** if they already confirmed, send a short reminder and don't ask for a reply. If they have not confirmed, ask again.

6. If a patient replies with a problem, the automatic messages stop and the front desk handles it.

7. A patient who confirms early does not get the day 6 or day 3 requests, they still get the day 1 reminder because agreeing to come and remembering to come are two different things.

---

## Regarding contact permissions

1. I keep permission separate for text and for email. If one channel is not allowed, use the other one if it is allowed. If a patient texts STOP, that clinic does not text that number again.

2. The messages only say the clinic, the date, and the time. No patient names, no procedures, no links. I would rather send less and be safe.

3. There was an online portal that went with the emails but I removed it started feeling like I was over engineering this.

---

## Matching a reply to the right appointment

A short yes can confirm an appointment, but only if it clearly matches one appointment. If the same phone number covers more than one patient or more than one appointment, I don't guess, that goes to the front desk. Same with no, same with "yes but call me" you could use AI here and I would probably use JEV in this case but for this take home assignment I stuck with just checking it programmatically, anything that isn't specifically a version of yes and nothing added to that yes gets looked at.

If the appointment time changes, the old confirmation does not count anymore, the patient has to confirm the new time. If only the provider or the length of the appointment changes, the confirmation still counts because the time they agreed to did not change.

Saying yes is not the same as showing up. The leadership numbers keep those separate. A yes means they confirmed. The PMS status says what actually happened with the appointment.

---

## Vendor choice

For real sending, I would start with Twilio for text messages and Amazon SES for email.

### Here is why

- **Twilio SendGrid email** is not HIPAA eligible. Twilio explicitly says it cannot sign BAAs for SendGrid and customers should not use it for PHI. Adding encryption yourself does not change its eligibility

- **Amazon SES** Is on AWS's HIPAA-eligible services list. Using it for PHI requires an AWS BAA and appropriate configuration

Before using them for real, somebody needs to check Apex's contracts, the pricing, and the BAA side of it, including the replies and the logs, not just the sending.

Cost is a real issue here. At 4000 appointments a day the messages add up fast and a system like this can end up costing a lot, especially if we end up with 1000+ locations.

I've run into this before where something that's very tiny at first glance can become a massive bill at WeInfuse https://www.dynamsoft.com/  I believe was an example of one that got out of hand related to pdf scanning its been a couple years don't quote me on that.

---

## If I Had Another Week I Would

1. **I’d spend more time refining the coding guide I built for my AI harness.** I wanted human readability to be something I deliberately reviewed alongside whether the code worked. I used books like *Eloquent Ruby*, *Practical Object-Oriented Design in Ruby*, and *99 Bottles of OOP* to give that review a foundation.

Given the time available, I had AI gather guidance across the chapters to get broad coverage quickly. That gave me a starting point, but the current guide is too large. I’d like to go through the books chapter by chapter myself, cherry-pick the principles I actually want in my workflow, and check the older advice against current Ruby and Rails practices. I want a smaller, sharper guide where I understand and can explain why each rule earned its place.

My harness hadn’t already included this level of review because I’ve been working independently since incorporating AI into my workflow. I hadn’t had the same need to hand code to teammates for review and maintenance. This exercise exposed that gap and gave me a concrete way to improve it.

Thank y'all again for this exercise. It gave me a concrete way to improve how I build.
