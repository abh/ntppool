-- the static part: the servers etc.



alter database default character set 'utf8';

CREATE TABLE `users` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `email` varchar(255) NOT NULL default '',
  `name` varchar(255) default NULL,
  `pass` varchar(255) default NULL,
  `nomail` enum('0','1') NOT NULL default '0',
  `bitcard_id` char(40) default NULL,
  `username` varchar(40) default NULL,
  `public_profile` tinyint(1) not null default 0,
  `organization_name` varchar(150) default NULL,
  `organization_url` varchar(150) default NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `email` (`email`),
  UNIQUE KEY `users_email_key` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE servers (
    id int unsigned primary key auto_increment,
    ip varchar(15) NOT NULL unique,
    admin int unsigned not null,
    hostname varchar(255),
    stratum tinyint unsigned default NULL,
    in_pool tinyint unsigned NOT NULL,
    in_server_list tinyint unsigned NOT NULL,
    netspeed mediumint(8) unsigned NOT NULL default '1000',
    created_on datetime default NULL,
    updated_on timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
    index (admin),
    CONSTRAINT admin FOREIGN KEY (admin) REFERENCES users(id)
) engine=INNODB;

CREATE TABLE server_notes (
    id int unsigned primary key auto_increment,
    server int unsigned not null,
    name varchar(255) not null,
    note text not null,
    unique key (server,name),
    key (name),
    CONSTRAINT FOREIGN KEY (server) REFERENCES servers(id) ON DELETE CASCADE
) ENGINE=INNODB;

CREATE TABLE zones (
    id int unsigned primary key auto_increment,
    name varchar(255) NOT NULL UNIQUE,
    description varchar(255) default NULL,
    parent int(10) unsigned default NULL,
    dns tinyint(1) NOT NULL DEFAULT 1,
    KEY (parent),
    FOREIGN KEY (parent) REFERENCES zones(id)
) ENGINE=INNODB;

CREATE TABLE locations (
    id int unsigned primary key auto_increment,
    server int unsigned not null,
    zone   int unsigned not null,
    UNIQUE (server, zone),
    constraint locations_server FOREIGN KEY (server) REFERENCES servers(id) ON DELETE CASCADE,
    constraint locations_zone   FOREIGN KEY (zone) REFERENCES zones(id) ON DELETE CASCADE
) ENGINE=INNODB;

-- the dynamic part: logging
CREATE TABLE log_scores (
    id int not null auto_increment primary key,
    server INTEGER unsigned NOT NULL,
    ts timestamp NOT NULL,
    score REAL NOT NULL,
    step REAL NOT NULL,
    offset REAL,
    key (server,ts),
    constraint log_scores_server FOREIGN KEY (server) REFERENCES servers(id) ON DELETE CASCADE
) ENGINE=INNODB;

-- this is a different table from 'servers' since it changes a lot
-- and in a different table from 'log' as we only store the current score
CREATE TABLE scores (
    server INTEGER unsigned NOT NULL UNIQUE,
    ts TIMESTAMP not null,
    score REAL NOT NULL DEFAULT 0.0,
    constraint scores_server FOREIGN KEY (server) REFERENCES servers(id) ON DELETE CASCADE
) ENGINE=INNODB;


-- integrating automatic checking/reporting of unreachable servers
CREATE TABLE server_alerts (
    server INT unsigned  NOT NULL primary key,
    last_score REAL NOT NULL DEFAULT 0.0,
    first_email_time datetime,
    last_email_time datetime,
    constraint unusable_servers_server foreign key (server) REFERENCES servers(id) ON DELETE CASCADE
) ENGINE=INNODB;


CREATE TABLE `zone_server_counts` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `zone` int unsigned NOT NULL,
  `date` date NOT NULL,
  `count_active` mediumint(8) unsigned NOT NULL,
  `count_registered` mediumint(8) unsigned NOT NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `zone` (`zone`,`date`),
  constraint zone_server_counts foreign key (zone) references zones(id) on delete cascade
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


CREATE TABLE `user_privileges` (
  `user` int(10) unsigned NOT NULL default '0',
  `see_all_servers` tinyint(1) not null default 0,
  `see_all_user_profiles` tinyint(1) NOT NULL default '0',
  UNIQUE KEY `user` (`user`),
  CONSTRAINT `user_privileges` FOREIGN KEY (`user`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE server_urls (
  `id` int(10) unsigned NOT NULL auto_increment primary key,
  server INT unsigned  NOT NULL,
  url  varchar(255) not null,
  key (server),
  constraint server_urls_server foreign key (server) REFERENCES servers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

