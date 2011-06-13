use inc::Module::Install;

name 'Brahman';
all_from 'lib/Brahman.pm';

requires 'AnyEvent';
requires 'AnyEvent::Handle';
requires 'Class::Load';
requires 'Config::INI::Reader';
requires 'Mouse';
requires 'Router::Simple';
requires 'Task::Weaken';
requires 'Twiggy';

WriteAll;