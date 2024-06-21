# Use an official Ruby runtime as a parent image
FROM ruby:2.7

# Set the working directory
WORKDIR /usr/src/app

# Install necessary packages
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy the Gemfile and Gemfile.lock into the image
COPY Gemfile Gemfile.lock ./

# Install any needed gems specified in Gemfile
RUN bundle install

# Copy the rest of the application code
COPY . .

# Make the make.sh script executable
RUN chmod +x make.sh

# Expose port 3000 (or the port you need)
EXPOSE 3000

# Command to run your script
CMD ["./make.sh"]
