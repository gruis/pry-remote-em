class Pry
  # If the Pry instance reponds to :_pryem_ and Pry#_pryem_ is not nil
  # then that instance of Pry is part of a pry-remote-em server.
  attr_reader :_pryem_
end
