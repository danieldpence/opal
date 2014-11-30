require 'opal/nodes/scope'

module Opal
  module Nodes
    # FIXME: needs rewrite
    class DefNode < ScopeNode
      handle :def

      children :recvr, :mid, :args, :stmts

      def compile
        jsid = mid_to_jsid mid.to_s
        params = nil
        scope_name = nil

        opt = args[1..-1].select { |a| a.first == :optarg }

        argc = args.length - 1

        # block name (&block)
        if given_block = args[1..-1].find { |a| a.first == :blockarg }
          block_name = variable(given_block[1]).to_sym
          argc -= 1
        end

        # splat args *splat
        if restarg = args[1..-1].find { |a| a.first == :restarg }
          uses_splat = true
          if restarg[1]
            splat = restarg[1].to_sym
            argc -= 1
          else
            argc -= 1
          end
        end

        if compiler.arity_check?
          arity_code = arity_check(args, opt, uses_splat, block_name, mid)
        end

        in_scope do
          scope.mid = mid
          scope.defs = true if recvr

          if block_name
            scope.uses_block!
            scope.add_arg block_name
          end

          yielder = block_name || '$yield'
          scope.block_name = yielder

          params = process(args)
          stmt_code = stmt(compiler.returns(stmts))

          add_temp 'self = this'

          line "#{variable(splat)} = $slice.call(arguments, #{argc});" if splat

          opt.each do |o|
            next if o[2][2] == :undefined
            line "if (#{variable(o[1])} == null) {"
            line "  #{variable(o[1])} = ", expr(o[2])
            line "}"
          end

          # must do this after opt args incase opt arg uses yield
          scope_name = scope.identity

          if scope.uses_block?
            add_temp "$iter = #{scope_name}.$$p"
            add_temp "#{yielder} = $iter || nil"

            line "#{scope_name}.$$p = null;"
          end

          unshift "\n#{current_indent}", scope.to_vars
          line stmt_code

          unshift arity_code if arity_code

          unshift "var $zuper = $slice.call(arguments, 0);" if scope.uses_zuper

          if scope.catch_return
            unshift "try {\n"
            line "} catch ($returner) { if ($returner === Opal.returner) { return $returner.$v }"
            push " throw $returner; }"
          end
        end

        unshift ") {"
        unshift(params)
        unshift "function("
        unshift "#{scope_name} = " if scope_name
        line "}"

        if recvr
          unshift 'Opal.defs(', recv(recvr), ", '$#{mid}', "
          push ')'
        elsif uses_defn?(scope)
          wrap "Opal.defn(self, '$#{mid}', ", ')'
        elsif scope.class?
          unshift "#{scope.proto}#{jsid} = "
        elsif scope.sclass?
          unshift "self.$$proto#{jsid} = "
        elsif scope.top?
          unshift "Opal.Object.$$proto#{jsid} = "
        else
          unshift "def#{jsid} = "
        end

        wrap '(', ", nil) && '#{mid}'" if expr?
      end

      # Simple helper to check whether this method should be defined through
      # `Opal.defn()` runtime helper.
      #
      # @param [Opal::Scope] scope
      # @returns [Boolean]
      #
      def uses_defn?(scope)
        if scope.iter? or scope.module?
          true
        elsif scope.class? and %w(Object BasicObject).include?(scope.name)
          true
        else
          false
        end
      end

      # Returns code used in debug mode to check arity of method call
      def arity_check(args, opt, splat, block_name, mid)
        meth = mid.to_s.inspect

        arity = args.size - 1
        arity -= (opt.size)
        arity -= 1 if splat
        arity -= 1 if block_name
        arity = -arity - 1 if !opt.empty? or splat

        # $arity will point to our received arguments count
        aritycode = "var $arity = arguments.length;"

        if arity < 0 # splat or opt args
          aritycode + "if ($arity < #{-(arity + 1)}) { Opal.ac($arity, #{arity}, this, #{meth}); }"
        else
          aritycode + "if ($arity !== #{arity}) { Opal.ac($arity, #{arity}, this, #{meth}); }"
        end
      end
    end

    # def args list
    class ArgsNode < Base
      handle :args

      def compile
        children.each_with_index do |child, idx|
          next if :blockarg == child.first
          next if :restarg == child.first and child[1].nil?

          child = child[1].to_sym
          push ', ' unless idx == 0
          child = variable(child)
          scope.add_arg child.to_sym
          push child.to_s
        end
      end
    end
  end
end
