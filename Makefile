all             :; forge build
clean           :; forge clean
                    # Usage example: make test match=SpellIsCast
test            :; ./test-dss-gate.sh
deploy          :; make && forge create Gate1
