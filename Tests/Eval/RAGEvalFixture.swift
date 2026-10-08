import Foundation

/// SYNTHETIC notes fixture and question set for the "ask your notes" eval.
/// Every note and question was written for this eval: the people, companies
/// and numbers are invented. Several notes share vocabulary on purpose
/// (two budgets, two trips, two hiring notes) so keyword overlap alone is
/// not enough, and a handful of questions use different words from the note
/// they need (marked `paraphrased`), which is what the embedding half of the
/// hybrid retriever is for.
///
/// Each question names exactly one relevant note and an answer span: a
/// phrase copied from that note that a correct answer must contain. Spans sit
/// inside one sentence, so they can never straddle a passage boundary.
enum RAGEvalFixture {
    struct Question {
        let question: String
        let note: String
        let span: String
        var paraphrased = false
    }

    static let notes: [(title: String, body: String)] = [
        ("Offsite logistics",
         "The offsite is in Porto from the 14th to the 16th. The venue is the Casa do Rio and it holds 40 people. Flights from London land at 11:20 on Thursday. A minibus collects everyone from the airport. Dinner on the first night is at Taberna Velha, booked for 38."),
        ("Offsite agenda",
         "Day one is strategy: the three-year plan and the pricing reset. Day two is team health, run by an outside facilitator called Mira Santos. Day three is a half day and ends with lunch at noon. Laptops stay closed during the facilitator sessions."),
        ("Brand voice",
         "Our voice is confident, plain and never loud. We write short sentences and avoid superlatives. We never use exclamation marks in product copy. Headlines state a benefit, not a feature."),
        ("Pricing research",
         "Annual plans convert better than monthly plans in every cohort we tested. A 20 percent annual discount tested best; 30 percent did not lift conversion further. Churn on annual plans is about a third of monthly churn. Enterprise buyers asked for invoicing in euros."),
        ("Budget Q3",
         "Marketing spend is capped at 50 thousand for the quarter. Travel is frozen until September except for the offsite. Contractor budget is 18 thousand and is already two thirds committed. Any purchase above 5 thousand needs sign-off from Dana."),
        ("Budget Q4 draft",
         "The Q4 draft raises marketing to 70 thousand for the launch. Headcount stays flat until January. The events line is 12 thousand, mostly for the Berlin conference booth. Finance wants the final numbers by the 30th."),
        ("Hiring plan",
         "We need two backend engineers and one product designer by October. Interviews run in pairs and every loop includes a written exercise. The designer role reports to Ines. Offers above band need approval from the CFO."),
        ("Interview notes: Theo",
         "Theo has six years of Swift experience and shipped two consumer apps. Strong on testing and performance, weaker on product sense. He is available from the first of November. Salary expectation is at the top of the band."),
        ("Security review",
         "Signing keys are rotated every quarter. The audit found no critical issues and two medium ones. The medium issues are verbose logging in the sync service and a missing rate limit on login. Both are due to be fixed before the November release."),
        ("Customer interviews",
         "Eleven customers were interviewed in August. Most asked for offline mode and faster search. Two asked for a home screen widget. Three said onboarding took too long, mostly because of the import step. Nobody asked for more integrations."),
        ("Kickoff with the studio",
         "The studio proposed three directions: Editorial, Instrument and Atelier. The team leaned towards Instrument because it reads well at small sizes. The studio's fee is fixed at 24 thousand for six weeks. First concepts are due on the 9th."),
        ("Garden",
         "Tomatoes go in after the last frost, usually mid-May here. Water the basil every morning in summer. The raised bed by the fence gets the most sun. Compost is turned every two weeks."),
        ("Recipe: dal",
         "Rinse the red lentils until the water runs clear. Temper cumin and mustard seeds in ghee, then add garlic and ginger. Simmer the lentils with turmeric for 25 minutes. Finish with lemon juice and fresh coriander."),
        ("Car maintenance",
         "The tyres need rotating every 10 thousand kilometres. The next service is at 60 thousand kilometres. Insurance renews in March and the broker is Hollis and Grey. The spare key is in the kitchen drawer."),
        ("Meeting notes: roadmap sync",
         "Sarah owns the feedback round for the beta. Sam will send the revised deck by Friday. We agreed to cut the tablet layout from the first release. The next sync moves to Tuesdays at ten."),
        ("Meeting notes: vendor call",
         "The print vendor needs artwork as PDF with three millimetres of bleed. Their lead time is ten working days. They offered a 5 percent discount for orders above 2,000 units. Payment terms are thirty days from invoice."),
        ("Reading: Alexander",
         "Places feel alive when their patterns resolve real forces. Copy the force, not the form. A good pattern can be explained to someone in a single sentence. Alexander's examples are mostly about towns and buildings."),
        ("Home move checklist",
         "The lease on the new flat starts on the 1st of December. Movers are booked for the 2nd and quoted 1,450 for the day. Internet installation is scheduled for the 4th. Meter readings must be sent to the supplier on moving day."),
        ("Health",
         "The dentist check-up is every six months, next one in January. The physiotherapist suggested stretching the hamstrings twice a day. Blood test results were all in the normal range. The repeat prescription renews at the end of each month."),
        ("Podcast ideas",
         "Episode one could be about building software for people who work offline. A possible guest is Lena Park, who runs a field research team. Episodes should stay under thirty minutes. Record in the small meeting room because it has the least echo."),
        ("Investor update draft",
         "Revenue grew 14 percent quarter on quarter. Runway is 22 months at the current burn. The main risk is a slower enterprise sales cycle than planned. The ask this quarter is introductions to two design partners."),
        ("Travel: Berlin conference",
         "The Berlin conference runs from the 6th to the 8th of November. The booth is number 41 in hall B. The hotel is the Spreeblick, five minutes from the venue. Train tickets are booked; the return is on the 8th at 18:05."),
    ]

    static let questions: [Question] = [
        // Offsite logistics / agenda
        .init(question: "How many people does the offsite venue hold?", note: "Offsite logistics", span: "holds 40 people"),
        .init(question: "When do the flights from London land?", note: "Offsite logistics", span: "land at 11:20 on Thursday"),
        .init(question: "Where is dinner on the first night of the offsite?", note: "Offsite logistics", span: "Taberna Velha"),
        .init(question: "How do people get from the airport to the offsite?", note: "Offsite logistics", span: "A minibus collects everyone"),
        .init(question: "Who runs the team health day?", note: "Offsite agenda", span: "Mira Santos"),
        .init(question: "When does day three of the offsite end?", note: "Offsite agenda", span: "ends with lunch at noon"),
        .init(question: "Can we use laptops during the facilitator sessions?", note: "Offsite agenda", span: "Laptops stay closed"),
        // Brand voice
        .init(question: "Do we use exclamation marks in product copy?", note: "Brand voice", span: "never use exclamation marks"),
        .init(question: "What should headlines state?", note: "Brand voice", span: "state a benefit, not a feature"),
        .init(question: "How should our writing sound?", note: "Brand voice", span: "confident, plain and never loud", paraphrased: true),
        // Pricing
        .init(question: "Which annual discount tested best?", note: "Pricing research", span: "20 percent annual discount"),
        .init(question: "How does churn on annual plans compare with monthly?", note: "Pricing research", span: "about a third of monthly churn"),
        .init(question: "What currency do enterprise buyers want to be invoiced in?", note: "Pricing research", span: "invoicing in euros"),
        .init(question: "Do yearly subscriptions sell better than month-to-month?", note: "Pricing research",
              span: "Annual plans convert better than monthly plans", paraphrased: true),
        // Budgets
        .init(question: "What is the marketing spend cap this quarter?", note: "Budget Q3", span: "capped at 50 thousand"),
        .init(question: "Who signs off purchases above 5 thousand?", note: "Budget Q3", span: "sign-off from Dana"),
        .init(question: "How much of the contractor budget is committed?", note: "Budget Q3", span: "two thirds committed"),
        .init(question: "What does the Q4 draft raise marketing to?", note: "Budget Q4 draft", span: "70 thousand"),
        .init(question: "What is the events line in the Q4 draft for?", note: "Budget Q4 draft", span: "Berlin conference booth"),
        .init(question: "When does finance want the final Q4 numbers?", note: "Budget Q4 draft", span: "by the 30th"),
        // Hiring
        .init(question: "How many backend engineers are we hiring?", note: "Hiring plan", span: "two backend engineers"),
        .init(question: "Who does the designer role report to?", note: "Hiring plan", span: "reports to Ines"),
        .init(question: "Who approves offers above band?", note: "Hiring plan", span: "approval from the CFO"),
        .init(question: "How many years of Swift experience does Theo have?", note: "Interview notes: Theo", span: "six years of Swift experience"),
        .init(question: "When is Theo available to start?", note: "Interview notes: Theo", span: "first of November"),
        .init(question: "What was Theo weaker on?", note: "Interview notes: Theo", span: "weaker on product sense"),
        // Security
        .init(question: "How often are signing keys rotated?", note: "Security review", span: "rotated every quarter"),
        .init(question: "What were the medium issues from the audit?", note: "Security review", span: "verbose logging in the sync service"),
        .init(question: "Did the security audit find anything serious?", note: "Security review", span: "no critical issues", paraphrased: true),
        // Customers
        .init(question: "How many customers were interviewed in August?", note: "Customer interviews", span: "Eleven customers"),
        .init(question: "What did most customers ask for?", note: "Customer interviews", span: "offline mode and faster search"),
        .init(question: "Why did onboarding take too long?", note: "Customer interviews", span: "because of the import step"),
        // Studio
        .init(question: "Which direction did the team lean towards with the studio?", note: "Kickoff with the studio", span: "leaned towards Instrument"),
        .init(question: "What is the studio's fee?", note: "Kickoff with the studio", span: "fixed at 24 thousand"),
        .init(question: "When are the first concepts due from the studio?", note: "Kickoff with the studio", span: "due on the 9th"),
        // Home and life
        .init(question: "When do tomatoes go in?", note: "Garden", span: "after the last frost"),
        .init(question: "Which bed gets the most sun?", note: "Garden", span: "raised bed by the fence"),
        .init(question: "How long do the lentils simmer?", note: "Recipe: dal", span: "for 25 minutes"),
        .init(question: "What spices are tempered in ghee for the dal?", note: "Recipe: dal", span: "cumin and mustard seeds"),
        .init(question: "When does the car insurance renew?", note: "Car maintenance", span: "renews in March"),
        .init(question: "Where is the spare car key?", note: "Car maintenance", span: "in the kitchen drawer"),
        .init(question: "When is the next car service due?", note: "Car maintenance", span: "60 thousand kilometres"),
        // Meetings
        .init(question: "Who owns the beta feedback round?", note: "Meeting notes: roadmap sync", span: "Sarah owns the feedback round"),
        .init(question: "What did we cut from the first release?", note: "Meeting notes: roadmap sync", span: "cut the tablet layout"),
        .init(question: "When will Sam send the revised deck?", note: "Meeting notes: roadmap sync", span: "by Friday"),
        .init(question: "How much bleed does the print vendor need?", note: "Meeting notes: vendor call", span: "three millimetres of bleed"),
        .init(question: "What is the print vendor's lead time?", note: "Meeting notes: vendor call", span: "ten working days"),
        .init(question: "When do we have to pay the printer?", note: "Meeting notes: vendor call", span: "thirty days from invoice", paraphrased: true),
        // Reading, move, health
        .init(question: "What makes places feel alive?", note: "Reading: Alexander", span: "patterns resolve real forces"),
        .init(question: "When does the lease on the new flat start?", note: "Home move checklist", span: "1st of December"),
        .init(question: "How much did the movers quote?", note: "Home move checklist", span: "quoted 1,450"),
        .init(question: "When is the internet being installed in the new flat?", note: "Home move checklist", span: "scheduled for the 4th"),
        .init(question: "How often is the dentist check-up?", note: "Health", span: "every six months"),
        .init(question: "What did the physiotherapist suggest?", note: "Health", span: "stretching the hamstrings"),
        // Podcast, investors, travel
        .init(question: "Who could be a guest on the podcast?", note: "Podcast ideas", span: "Lena Park"),
        .init(question: "Where should we record the podcast?", note: "Podcast ideas", span: "small meeting room"),
        .init(question: "How much did revenue grow quarter on quarter?", note: "Investor update draft", span: "grew 14 percent"),
        .init(question: "How long is our runway?", note: "Investor update draft", span: "22 months"),
        .init(question: "What booth number do we have in Berlin?", note: "Travel: Berlin conference", span: "number 41 in hall B"),
        .init(question: "Which hotel are we staying at for the Berlin conference?", note: "Travel: Berlin conference", span: "Spreeblick"),
        .init(question: "How much money are we burning, and how long will it last?", note: "Investor update draft",
              span: "Runway is 22 months", paraphrased: true),
    ]
}
