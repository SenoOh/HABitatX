FROM ruby:3.0

WORKDIR /var/www
COPY ./src /var/www

RUN bundle config --local set path 'vendor/bundle'\
    && bundle install

CMD ["bundle", "exec", "ruby", "habitatx.rb", "-o", "0.0.0.0"]