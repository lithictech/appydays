install:
	bundle install
cop:
	bundle exec rubocop
fix:
	bundle exec rubocop --autocorrect-all
fmt: fix

test:
	RACK_ENV=test bundle exec rspec spec/
testf:
	RACK_ENV=test bundle exec rspec spec/ --fail-fast --seed=1

build:
	gem build appydays.gemspec
	# gem publish appydays-x.y.z.gem
