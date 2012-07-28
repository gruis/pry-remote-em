require "digest/md5"

# Moneky-patch the invoke_editor helper to send the edit request to the requesting client
# if the the pry session is a remote session. This file should only be loaded by a
# pry-remote-em server.
class Pry
  module Helpers
    module CommandHelpers
      alias :invoke_editor_orig :invoke_editor
      def invoke_editor(file, line, reloading)
        if _pry_.respond_to?(:_pryem_) && _pry_._pryem_
          contents = IO.read(file)
          chksum   = Digest::MD5.hexdigest(contents)
          edited   = _pry_._pryem_.invoke_editor(file, line, contents)
          return unless edited
          if chksum != Digest::MD5.hexdigest(IO.read(file))
            # TODO send a diff
            return unless _pry_._pryem_.update_changed(file, line)
          end
          File.open(file, "w") { |f| f.write(edited) }
        else
          invoke_editor_orig(file, line, reloading)
        end
      end
    end
  end
end
