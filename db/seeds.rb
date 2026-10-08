# This file seeds the database with a starting set of users and tasks. Load it
# with `bin/rails db:seed` (or alongside db:create via `bin/rails db:setup`).
#
# All accounts share the password "abc123" so any of them can be used to log in.

[
  "Ada Lovelace",
  "Grace Hopper",
  "Katherine Johnson",
  "Alan Turing",
  "Edsger Dijkstra"
].each_with_index do |name, index|
  User.where(email: "user#{index + 1}@tern.travel").first_or_create!(
    name: name,
    password: "abc123",
    password_confirmation: "abc123"
  )
end

ada = User.find_by!(email: "user1@tern.travel")
grace = User.find_by!(email: "user2@tern.travel")
katherine = User.find_by!(email: "user3@tern.travel")
today = Date.current

# Titles intentionally vary in casing, length, and shared substrings (several
# "Book ...", two "... client ...") so filtering and sorting have something real
# to chew on. A few descriptions are left blank to exercise the index view's
# nil-safe truncation.
#
# Due dates are relative to today so that logging in as user1@tern.travel (Ada)
# shows a populated "Due Soon" section and the reminder rake task has mail to
# send. The spread sits on both sides of each edge of the 7-day window, and the
# near-dated complete, unassigned, and other-user tasks show what is left out.
tasks = [
  {title: "Book flights to Lisbon", complete: true, assignee: ada, due_date: today + 1.day, description: "Outbound May 3, return May 17. Aisle seats for both legs."},
  {title: "Book hotel in Kyoto", complete: false, assignee: ada, due_date: today + 2.days, description: "Ryokan near Gion, 4 nights, breakfast included."},
  {title: "Book airport transfer", complete: false, assignee: ada, due_date: today, description: nil},
  {title: "Confirm client itinerary", complete: false, assignee: ada, due_date: today + 1.day, description: "Send the day-by-day plan to the Hendricks party for sign-off."},
  {title: "Email client welcome packet", complete: true, assignee: grace, due_date: nil, description: "Visa reminders, packing list, emergency contacts."},
  {title: "Renew passport", complete: false, assignee: ada, due_date: today + 7.days, description: "Expedited — current one expires in under six months."},
  {title: "Update travel insurance", complete: false, assignee: ada, due_date: today + 8.days, description: nil},
  {title: "Draft Q3 trip budget", complete: false, assignee: ada, due_date: today - 3.days, description: "Roll up supplier quotes and a 12% contingency."},
  {title: "Review supplier contracts", complete: true, assignee: katherine, due_date: nil, description: "Check cancellation windows before the deposit deadline."},
  {title: "Schedule team offsite", complete: false, assignee: ada, due_date: today + 14.days, description: "Two days, somewhere reachable by train for everyone."},
  {title: "Reconcile expense report", complete: false, assignee: grace, due_date: today + 1.day, description: "March card statement against the receipts folder."},
  {title: "Plan Patagonia route", complete: false, assignee: nil, due_date: today + 2.days, description: "El Chaltén to Torres del Paine, padding for weather days."},
  {title: "Order currency for Japan", complete: false, assignee: nil, due_date: today + 1.day, description: nil},
  {title: "Sync with ground operator", complete: true, assignee: katherine, due_date: today - 1.day, description: "Confirm the driver and guide for the Marrakech leg."},
  {title: "Archive old itineraries", complete: false, assignee: nil, due_date: nil, description: "Anything from last season can move to cold storage."},
  {title: "follow up with Lisbon hotel", complete: false, assignee: ada, due_date: nil, description: "Lowercase on purpose — still waiting on the room upgrade."}
]

tasks.each do |attributes|
  Task.find_or_initialize_by(title: attributes[:title]).update!(attributes.except(:title))
end

legacy_tasks = [
  {title: "Buy tickets: book the 9am AA flight to Cancun", complete: false},
  {title: "Call hotel: confirm the late checkout for the Rivera party", complete: false},
  {title: "Passport: renew before the Japan trip", complete: true},
  {title: "Insurance: add the Patagonia leg to the policy", complete: false}
]

legacy_tasks.each do |attributes|
  Task.where(title: attributes[:title]).first_or_create!(attributes.except(:title))
end
