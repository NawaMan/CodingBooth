# Rails Example

A starting point for [Ruby on Rails](https://rubyonrails.org/) on Postgres inside a CodingBooth workspace.

Unlike most other examples, this one **does not commit the full Rails scaffold** — `rails new` generates 50+ files, most of which are templated identically per project. Instead, the Boothfile installs Ruby + Postgres + Rails as a gem, and the workflow is "scaffold once, then build your app".

## Run

```bash
./booth run
# inside the booth, scaffold the Rails app once:
rails new . --database=postgresql --skip-git --skip-bundle --force
bundle install

# point Rails at the local Postgres:
cat > config/database.yml <<EOF
default: &default
  adapter: postgresql
  encoding: unicode
  host: /var/run/postgresql
  username: $USER

development:
  <<: *default
  database: rails_demo_dev

test:
  <<: *default
  database: rails_demo_test
EOF

bin/rails db:create
bin/rails db:migrate
bin/rails server -b 0.0.0.0
```

Then open http://localhost:3000/ on the host — you should see the Rails welcome page.

## What's inside

- `.booth/Boothfile` — Ruby 3.3, Postgres (auto-starts), the Ruby VS Code extension, and `rails` installed via `install gem rails`.
- `.booth/config.toml` — exposes container port 3000.
- This README — the only handwritten content. Rails owns its own scaffold.

## Why no committed scaffold?

Rails projects are heavily template-generated; the diff between `rails new` and a hand-written equivalent is huge boilerplate that tends to drift between Rails versions. Letting `rails new` run inside the booth keeps the example aligned with whatever Rails version the gem install pulls.
