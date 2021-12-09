install:
	bundle install
cop:
	bundle exec rubocop
fix:
	bundle exec rubocop --auto-correct-all
fmt: fix

test:
	RACK_ENV=test bundle exec rspec spec/
testf:
	RACK_ENV=test bundle exec rspec spec/ --fail-fast --seed=1