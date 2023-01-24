VERSION := `cat lib/appydays/version.rb | grep 'VERSION =' | cut -d '"' -f2`

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
ifeq ($(strip $(VERSION)),)
	echo "Could not parse VERSION"
else
	git tag $(VERSION)
	gem build appydays.gemspec
	gem push appydays-$(VERSION).gem
	git push origin $(VERSION)
endif

