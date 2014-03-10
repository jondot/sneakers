require 'spec_helper'
require 'sneakers'

describe Sneakers::Utils do
  describe '::parse_workers' do
    before(:all) do
      class Foo; end
      class Bar; end
      class Baz
        class Quux; end
        class Corge; end
      end
    end

    describe 'given a single class name' do
      describe 'without namespace' do
        it 'returns the worker class name' do
          Sneakers::Utils.parse_workers('Foo').must_equal([[Foo],[]])
        end
      end

      describe 'with namespace' do
        it 'returns the worker class name' do
          Sneakers::Utils.parse_workers('Baz::Quux').must_equal([[Baz::Quux],[]])
        end
      end
    end

    describe 'given a list of class names' do
      describe 'without namespaces' do
        it 'returns all worker class names' do
          Sneakers::Utils.parse_workers('Foo,Bar').must_equal([[Foo,Bar],[]])
        end
      end

      describe 'with namespaces' do
        it 'returns all worker class names' do
          workers = Sneakers::Utils.parse_workers('Baz::Quux,Baz::Corge')
          workers.must_equal([[Baz::Quux,Baz::Corge],[]])
        end
      end
    end
  end
end
