use inc::Module::Install;

name 'Brahman';

requires 'AnyEvent';
requires 'Class::Load';
requires 'Config::INI::Reader';
requires 'Mouse';
requires 'Router::Simple';
requires 'Task::Weaken';
requires 'Twiggy';

WriteAll;